//
// Copyright (c) 2015, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

`include "cci_mpf_if.vh"
`include "cci_mpf_csrs.vh"

`include "cci_mpf_shim_vtp_params.h"


//
// Map virtual to physical addresses.  The AFU and FIU interfaces are thus
// different widths.
//
// Requests coming from the AFU can be tagged as containing either virtual
// or physical addresses.  Physical addresses are passed directly to the
// FIU without translation here.  The tag is accessed with the
// getReqAddrIsVirtual() function.
//
//                             * * * * * * * *
//
//   This module freely reorders memory references, including load/store
//   and store/store order without comparing addresses.  This is a standard
//   property of CCI.  If order is important in your memory subsystem then
//   requests coming from an AFU should be filtered by address before
//   reaching this module to guarantee order within a line.
//   cci_mpf_shim_write_order.sv provides this function and is included in the
//   reference memory subsystem.
//
//                             * * * * * * * *
//

// Index of an aligned physical page
typedef logic [CCI_PT_PA_IDX_BITS-1 : 0] t_TLB_PHYSICAL_IDX;

// Address hash index in the host memory page table
typedef logic [CCI_PT_VA_IDX_BITS-1 : 0] t_PTE_VA_HASH_IDX;

// Index (pointer) to line in the page table
typedef logic [CCI_PT_LINE_IDX_BITS-1 : 0] t_PTE_IDX;

// Address of a virtual page without the page offset bits
typedef logic [CCI_PT_VA_BITS-CCI_PT_PAGE_OFFSET_BITS-1 : 0] t_TLB_VA_PAGE;

module cci_mpf_shim_vtp
  #(
    // The TLB needs to generate loads internally in order to walk the
    // page table.  The reserved bit in Mdata is a location offered
    // to the page table walker to tag internal loads.  The Mdata location
    // must be zero on all requests flowing in to the TLB through the
    // afu interface below.
    //
    // Some shims (e.g. cci_mpf_shim_sort_responses) already manage Mdata and
    // guarantee that some high bits will be zero.
    parameter RESERVED_MDATA_IDX = -1
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    // CSRs
    cci_mpf_csrs.vtp csrs
    );

    logic reset;
    assign reset = fiu.reset;


    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    cci_mpf_if
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqC0Tx;
    logic deqC1Tx;

    cci_mpf_shim_buffer_afu
      #(
        .ENABLE_C0_BYPASS(1)
        )
      buffer
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqC0Tx,
         .deqC1Tx
         );

    assign afu_buf.reset = fiu.reset;

    //
    // Almost full signals in the buffered input are ignored --
    // replaced by deq signals and the buffer state.  Set them
    // to 1 to be sure they are ignored.
    //
    assign afu_buf.c0TxAlmFull = 1'b1;
    assign afu_buf.c1TxAlmFull = 1'b1;

    //
    // Validate parameter settings and that the Mdata reserved bit is 0
    // on all incoming read requests.
    //
    always_ff @(posedge clk)
    begin
        assert ((RESERVED_MDATA_IDX > 0) && (RESERVED_MDATA_IDX < CCI_MDATA_WIDTH)) else
            $fatal("cci_mpf_shim_vtp.sv: Illegal RESERVED_MDATA_IDX value: %d", RESERVED_MDATA_IDX);

        if (! reset)
        begin
            assert((afu_buf.c0Tx.hdr[RESERVED_MDATA_IDX] == 0) ||
                   ! afu_buf.c0Tx.valid) else
                $fatal("cci_mpf_shim_vtp.sv: AFU C0 Mdata[%d] must be zero", RESERVED_MDATA_IDX);
        end
    end


    // ====================================================================
    //
    //  Address mapping functions.
    //
    // ====================================================================

    // Similar to CCI_PT_PAGE_OFFSET_BITS but with line-based instead
    // of byte-based addresses.
    localparam LINE_PAGE_OFFSET_BITS = CCI_PT_PAGE_OFFSET_BITS -
                                       $clog2(CCI_CLDATA_WIDTH / 8);

    // Offset of a line within a page
    typedef logic [LINE_PAGE_OFFSET_BITS-1 : 0] t_VA_PAGE_OFFSET;

    // Given the virtual address of a line return the shortened VA of a page
    function automatic t_TLB_VA_PAGE pageFromVA;
        input t_cci_clAddr addr;

        return addr[$high(addr) : LINE_PAGE_OFFSET_BITS];
    endfunction

    // Given the virtual address of a line return the offset of the line from
    // the containing page.
    function automatic t_VA_PAGE_OFFSET pageOffsetFromVA;
        input t_cci_clAddr addr;

        return addr[LINE_PAGE_OFFSET_BITS-1 : 0];
    endfunction


    // ====================================================================
    //
    //  TLB
    //
    // ====================================================================

    // Lookup request to TLB
    t_TLB_VA_PAGE lookupPageVA[0:1];
    logic lookupEn[0:1];
    logic lookupRdy[0:1];

    // Lookup response from TLB
    t_TLB_PHYSICAL_IDX lookupRspPagePA[0:1];
    // Valid bit for lookupRspPagePA, returned two cycles after lookupEn is
    // high.  The TLB will automatically attempt to fetch a translation
    // if not valid is signaled.  The client is expected to retry requests
    // and the TLB will eventually respond with a valid signal.  The client
    // may also move on to other requests during miss processing.
    logic lookupValid[0:1];
    // Not present is an error signal. It means that the VA is not present
    // in the host-memory PTE.
    logic lookupNotPresent[0:1];

    // Request from the TLB to read a line in the host-memory page table.
    t_PTE_IDX tlbReadIdx;
    logic tlbReadIdxEn;

    // Response to page table read request
    t_cci_clData tlbReadData;
    logic tlbReadDataEn;

    cci_mpf_shim_vtp_assoc
      tlb
        (
         .clk,
         .reset,
         .lookupPageVA,
         .lookupEn,
         .lookupRdy,
         .lookupRspPagePA,
         .lookupValid,
         .lookupNotPresent,
         .tlbReadIdx,
         .tlbReadIdxEn,
         .tlbReadIdxRdy(csrs.vtp_in_page_table_base_valid),
         .tlbReadData,
         .tlbReadDataEn
         );

    always_ff @(posedge clk)
    begin
        if (! reset)
        begin
            assert (! lookupNotPresent[0] && ! lookupNotPresent[1]) else
                $fatal("cci_mpf_shim_vtp: VA not present in page table");
        end
    end

    // ====================================================================
    //
    //  TLB lookup pipeline
    //
    // ====================================================================

    //
    // Request data flowing through each channel
    //

    // Pipeline stage storage
    localparam AFU_PIPE_LAST_STAGE = 5;
    t_if_cci_mpf_c0_Tx c0_afu_pipe[0 : AFU_PIPE_LAST_STAGE];
    t_if_cci_mpf_c1_Tx c1_afu_pipe[0 : AFU_PIPE_LAST_STAGE];

    // Stage at which request is sent to TLB
    localparam AFU_PIPE_LOOKUP_STAGE = 1;

    // Stage to which retry wraps back
    localparam AFU_PIPE_RETRY_STAGE = 1;

    //
    // Work backwards in the pipeline.  First decide whether the oldest
    // request can fire.  If it can (or there is no request) then younger
    // requests will ripple through the pipeline.
    //

    // Is either AFU making a request?
    logic c0_request_rdy;
    assign c0_request_rdy =
        cci_mpf_c0TxIsValid(c0_afu_pipe[AFU_PIPE_LAST_STAGE]);

    logic c1_request_rdy;
    assign c1_request_rdy =
        cci_mpf_c1TxIsValid(c1_afu_pipe[AFU_PIPE_LAST_STAGE]);

    // Given a request, is the translation ready and can the request be
    // forwarded toward the FIU? TLB miss handler read requests have priority
    // on channel 0. lookupValid will only be set if there was a request.
    logic c0_fwd_req;
    assign c0_fwd_req =
        c0_request_rdy &&
        (lookupValid[0] ||
         ! cci_mpf_c0TxIsReadReq(c0_afu_pipe[AFU_PIPE_LAST_STAGE]) ||
         ! cci_mpf_c0_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
        ! fiu.c0TxAlmFull &&
        ! tlbReadIdxEn;

    logic c1_fwd_req;
    assign c1_fwd_req =
        c1_request_rdy &&
        (lookupValid[1] ||
         ! cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LAST_STAGE]) ||
         ! cci_mpf_c1_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
        ! fiu.c1TxAlmFull;

    // Did a request miss in the TLB or fail arbitration?  It will be rotated
    // back to the head of afu_pipe.
    logic c0_retry_req;
    assign c0_retry_req = c0_request_rdy && ! c0_fwd_req;

    logic c1_retry_req;
    assign c1_retry_req = c1_request_rdy && ! c1_fwd_req;


    //
    // Manage new requests coming from the AFU.
    //

    logic c0_new_req;
    assign c0_new_req = cci_mpf_c0TxIsValid(afu_buf.c0Tx);

    logic c1_new_req;
    assign c1_new_req = cci_mpf_c1TxIsValid(afu_buf.c1Tx);


    // Is there a WrFence request coming in on channel 1?  Since
    // the pipeline may reorder requests, all pending requests on
    // the channel 1 pipeline must drain before the fence can
    // proceed.
    logic c1_block_wrfence;

    always_comb
    begin
        c1_block_wrfence = 1'b0;

        // Is there something in the pipeline?
        for (int i = 0; i <= AFU_PIPE_LAST_STAGE; i = i + 1)
        begin
            c1_block_wrfence = c1_block_wrfence || c1_afu_pipe[i].valid;
        end

        // Is the next request a WrFence?
        c1_block_wrfence = c1_block_wrfence &&
                           cci_mpf_c1TxIsWriteFenceReq(afu_buf.c1Tx);
    end


    // Pass new requests to the afu_pipe?  Old retries have priority over
    // new requests.
    assign deqC0Tx = c0_new_req && ! c0_retry_req;
    assign deqC1Tx = c1_new_req && ! c1_retry_req && ! c1_block_wrfence;


    //
    // Advance the pipeline
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            for (int i = 0; i <= AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i] <= cci_mpf_c0Tx_clearValids();
                c1_afu_pipe[i] <= cci_mpf_c1Tx_clearValids();
            end
        end
        else
        begin
            // All but first two stages are a simple systolic pipeline
            for (int i = 1; i < AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i+1] <= c0_afu_pipe[i];
                c1_afu_pipe[i+1] <= c1_afu_pipe[i];
            end

            // Ready to accept new entries?
            if (! c0_retry_req)
            begin
                c0_afu_pipe[0] <= afu_buf.c0Tx;
            end

            if (! c1_retry_req)
            begin
                // Channel 1 is more complicated because it must block when
                // a WrFence is arriving until this pipeline is quiet.
                c1_afu_pipe[0].hdr   <= afu_buf.c1Tx.hdr;
                c1_afu_pipe[0].data  <= afu_buf.c1Tx.data;
                c1_afu_pipe[0].valid <= afu_buf.c1Tx.valid && ! c1_block_wrfence;
            end

            // Rotate failed lookup or advance pipeline?
            c0_afu_pipe[AFU_PIPE_RETRY_STAGE] <=
                c0_retry_req ? c0_afu_pipe[AFU_PIPE_LAST_STAGE] :
                               c0_afu_pipe[0];

            c1_afu_pipe[AFU_PIPE_RETRY_STAGE] <=
                c1_retry_req ? c1_afu_pipe[AFU_PIPE_LAST_STAGE] :
                               c1_afu_pipe[0];
        end
    end


    //
    // Tap afu_pipe to request translation from the TLB.  Translation is
    // skipped if the incoming request already has a physical address.
    //
    assign lookupPageVA[0] =
        pageFromVA(cci_mpf_c0_getReqAddr(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr));
    assign lookupEn[0] =
        lookupRdy[0] &&
        cci_mpf_c0TxIsReadReq(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE]) &&
        cci_mpf_c0_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr);

    assign lookupPageVA[1] =
        pageFromVA(cci_mpf_c1_getReqAddr(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr));
    assign lookupEn[1] =
        lookupRdy[1] &&
        cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE]) &&
        cci_mpf_c1_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr);


    // ====================================================================
    //
    //  Requests
    //
    // ====================================================================

    // Construct the read request header.
    t_cci_mpf_c0_ReqMemHdr c0_req_hdr;

    // Base address of the page table
    t_cci_clAddr page_table_base;
    assign page_table_base = csrs.vtp_in_page_table_base;

    always_comb
    begin
        if (! tlbReadIdxEn)
        begin
            //
            // Normal read.
            //
            c0_req_hdr = c0_afu_pipe[AFU_PIPE_LAST_STAGE].hdr;

            // Replace the address with the physical address
            if (cci_mpf_c0_getReqAddrIsVirtual(c0_req_hdr))
            begin
                // Page offset remains the same in VA and PA
                c0_req_hdr.base.address =
                    { lookupRspPagePA[0],
                      pageOffsetFromVA(c0_req_hdr.base.address) };
                c0_req_hdr.ext.addrIsVirtual = 0;
            end
        end
        else
        begin
            //
            // Read for TLB miss.
            //
            c0_req_hdr = cci_mpf_c0_genReqHdr(eREQ_RDLINE_S,
                                              page_table_base + tlbReadIdx,
                                              t_cci_mdata'(0),
                                              cci_mpf_defaultReqHdrParams(0));

            // Tag the request as a local page table walk
            c0_req_hdr[RESERVED_MDATA_IDX] = 1'b1;
        end
    end

    // Channel 0 (read) is either client requests or reads for TLB misses
    assign fiu.c0Tx = cci_mpf_genC0TxReadReq(c0_req_hdr, c0_fwd_req || tlbReadIdxEn);

    // Channel 1 request logic
    t_cci_mpf_c1_ReqMemHdr c1_req_hdr;
    t_VA_PAGE_OFFSET c1_req_offset;

    always_comb
    begin
        c1_req_hdr = c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr;

        // Request's line offset within the page.
        c1_req_offset = pageOffsetFromVA(c1_req_hdr.base.address);

        // Replace the address with the physical address
        if (cci_mpf_c1_getReqAddrIsVirtual(c1_req_hdr))
        begin
            c1_req_hdr.base.address = { lookupRspPagePA[1], c1_req_offset };
            c1_req_hdr.ext.addrIsVirtual = 0;
        end
    end

    // Update channel 1 header with translated address (writes) or pass
    // through original request (interrupt).
    always_comb
    begin
        fiu.c1Tx = cci_mpf_c1TxMaskValids(c1_afu_pipe[AFU_PIPE_LAST_STAGE],
                                         c1_fwd_req);

        // Is the header rewritten for a virtually addressed write?
        if (cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LAST_STAGE]))
        begin
            fiu.c1Tx.hdr = c1_req_hdr;
        end
    end


    // ====================================================================
    //
    //  Responses
    //
    // ====================================================================

    // Is the read response an internal page table reference?
    logic is_pt_rsp;
    assign is_pt_rsp = fiu.c0Rx.hdr[RESERVED_MDATA_IDX];

    always_comb
    begin
        afu_buf.c0Rx = fiu.c0Rx;

        // Connect read responses to the TLB management code
        tlbReadData = fiu.c0Rx.data;
        tlbReadDataEn = cci_c0Rx_isReadRsp(fiu.c0Rx) && is_pt_rsp;

        // Only forward client-generated read responses
        afu_buf.c0Rx.rspValid = fiu.c0Rx.rspValid && ! tlbReadDataEn;

        // Channel 1 (write) responses can flow directly from the FIU
        // port since there is no processing needed here.
        afu_buf.c1Rx = fiu.c1Rx;
    end


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign fiu.c2Tx = afu_buf.c2Tx;

endmodule // cci_mpf_shim_vtp


//
// Implement an associative TLB.  The TLB reflects the page table stored
// in host memory.  This TLB implementation is named "simple" because the
// page table has a very important property: once a translation is added
// to the software-side page table it may not be removed.  Consequently,
// the hardware-side TLB never needs to invalidate a translation.
// The FPGA logic can also depend on software-side page table pointers
// never becoming stale.  The only timing constraint in adding new pages
// is the software must guarantee that new page table entries are globally
// visible in system memory before passing a new virtual address to the FPGA.
//
module cci_mpf_shim_vtp_assoc
  #(
    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    //
    // There are two lookup ports, one for each CCI request channel.
    //

    // Look up VA in the table and return the PA or signal a miss two cycles
    // later.  The TLB code operates on aligned pages.  It is up to the caller
    // to compute offsets into pages.
    input  t_TLB_VA_PAGE lookupPageVA[0:1],
    input  logic lookupEn[0:1],         // Enable the request
    output logic lookupRdy[0:1],        // Ready to accept a request?

    // Respond with page's physical address two cycles after lookupEn
    output t_TLB_PHYSICAL_IDX lookupRspPagePA[0:1],
    // Signal lookupValid two cycles after lookupEn if the page
    // isn't currently in the FPGA-side translation table.
    output logic lookupValid[0:1],
    // Requested VA is not in the page table.  This is an error!
    output logic lookupNotPresent[0:1],

    // Request from the TLB to read a line from the shared-memory page table.
    // This will be triggered in response to a lookup miss.  Code that
    // instantiates this module is responsible for turning the request into
    // a read of the page table and forwarding the result to tlbReadData.
    output t_PTE_IDX tlbReadIdx,
    output logic tlbReadIdxEn,
    // System ready to accept a read request?
    input  logic tlbReadIdxRdy,

    // Response to page table read request
    input t_cci_clData tlbReadData,
    input logic tlbReadDataEn
    );

    // The TLB is associative.  Define the width of a set.
    localparam NUM_TLB_SET_WAYS = 4;

    // Number of sets in the FPGA-side TLB
    localparam NUM_TLB_SETS = 1024;
    localparam NUM_TLB_IDX_BITS = $clog2(NUM_TLB_SETS);
    typedef logic [NUM_TLB_IDX_BITS-1 : 0] t_TLB_IDX;

    // A virtual address tag is the remainder of the address after using
    // the low bits as a direct-mapped index to a TLB set.  NOTE: The
    // FPGA-side TLB tag is a different size from the host-side page table
    // tag!  This is because the page table hash size is different from
    // the FPGA's TLB hash size.  The page table hash is large because
    // we can afford a large table in host memory.  The TLB here is in
    // block RAM so is necessarily smaller.
    localparam TLB_VA_TAG_BITS = $bits(t_TLB_VA_PAGE) - NUM_TLB_IDX_BITS;
    typedef logic [TLB_VA_TAG_BITS-1 : 0] t_TLB_VIRTUAL_TAG;

    // A single TLB entry is a virtual tag and physical page index.
    typedef struct packed
    {
        t_TLB_VIRTUAL_TAG tag;
        t_TLB_PHYSICAL_IDX idx;
    }
    t_TLB_ENTRY;

    // Address tag in the page table (tag concatenated with hash index is
    // the virtual page.
    localparam CCI_PT_VA_TAG_BITS = CCI_PT_VA_BITS -
                                    CCI_PT_VA_IDX_BITS -
                                    CCI_PT_PAGE_OFFSET_BITS;

    typedef logic [CCI_PT_VA_TAG_BITS-1 : 0] t_PTE_VA_TAG;

    initial begin
        // Confirm that the VA size specified in VTP matches CCI.  The CCI
        // version is line addresses, so the units must be converted.
        assert (CCI_MPF_CLADDR_WIDTH + $clog2(CCI_CLDATA_WIDTH >> 3) ==
                CCI_PT_VA_BITS) else
            $fatal("cci_mpf_shim_vtp.sv: VA address size mismatch!");
    end

    // ====================================================================
    //
    //  Storage for the TLB.  Each way is stored in a separate memory in
    //  order to permit updating a way without a read-modify-write.
    //
    // ====================================================================

    // The address and write data are broadcast to all ways in a set
    t_TLB_IDX tlb_addr[0 : 1];

    // Write only uses port 1
    t_TLB_ENTRY tlb_wdata;
    logic tlb_wen[0 : NUM_TLB_SET_WAYS-1];

    // Read response.  We label registers in this pipeline relative to
    // the head of the flow.  The data is returned from the block RAM in
    // the second cycle, so we label the output tlb_rdata_qq to match
    // other registered signals.
    t_TLB_ENTRY tlb_rdata[0 : 1][0 : NUM_TLB_SET_WAYS-1];

    genvar w;
    generate
        for (w = 0; w < NUM_TLB_SET_WAYS; w = w + 1)
        begin: gen_tlb
            cci_mpf_prim_dualport_ram
              #(
                .N_ENTRIES(NUM_TLB_SETS),
                .N_DATA_BITS($bits(t_TLB_ENTRY)),
                .N_OUTPUT_REG_STAGES(1)
                )
              tlb(.clk0(clk),
                  .addr0(tlb_addr[0]),
                  .wen0(1'b0),
                  .wdata0('x),
                  .rdata0(tlb_rdata[0][w]),
                  .clk1(clk),
                  .addr1(tlb_addr[1]),
                  .wen1(tlb_wen[w]),
                  .wdata1(tlb_wdata),
                  .rdata1(tlb_rdata[1][w])
                  );
        end
    endgenerate


    //
    // Initialize the TLB.  The actual write will happen in a rule later
    // that arbitrates among read and write requests for port 1.
    //
    logic [$bits(t_TLB_IDX) : 0] init_idx;
    logic initialized;
    assign initialized = init_idx[$high(init_idx)];

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            init_idx <= 0;
        end
        else if (! initialized)
        begin
            init_idx <= init_idx + 1;
        end
    end


    // ====================================================================
    //
    //   Primary lookup pipeline.
    //
    // ====================================================================

    //
    // Structures holding state for each lookup pipeline stage
    //

    //
    // Primary state
    //
    typedef struct {
        logic did_lookup;
        logic [$bits(lookupPageVA)-1 : 0] lookup_page_va;
    } t_tlb_stage_state;

    localparam NUM_TLB_LOOKUP_PIPE_STAGES = 4;
    t_tlb_stage_state stg_state[1 : NUM_TLB_LOOKUP_PIPE_STAGES][0 : 1];

    // Pass primary state through the pipeline
    always_ff @(posedge clk)
    begin
        // Head of the pipeline: register data for stage 1
        for (int p = 0; p < 2; p = p + 1)
        begin
            if (reset)
            begin
                stg_state[1][p].did_lookup <= 0;
            end
            else
            begin
                stg_state[1][p].did_lookup <= lookupEn[p];
            end 

            stg_state[1][p].lookup_page_va <= lookupPageVA[p];
        end

        for (int s = 1; s < NUM_TLB_LOOKUP_PIPE_STAGES; s = s + 1)
        begin
            stg_state[s + 1] <= stg_state[s];
        end
    end

    // Return target TLB index for stage and port
    function automatic t_TLB_IDX target_tlb_idx(int stg, int p);
        t_TLB_VIRTUAL_TAG tag;
        t_TLB_IDX idx;
        { tag, idx } = stg_state[stg][p].lookup_page_va;
        return idx;
    endfunction

    // Return target TLB tag for stage and port
    function automatic t_TLB_VIRTUAL_TAG target_tlb_tag(int stg, int p);
        t_TLB_VIRTUAL_TAG tag;
        t_TLB_IDX idx;
        { tag, idx } = stg_state[stg][p].lookup_page_va;
        return tag;
    endfunction

    //
    // TLB read response data arrives in stage 2.
    //
    t_TLB_ENTRY stg_tlb_rdata[2 : NUM_TLB_LOOKUP_PIPE_STAGES][0 : 1][0 : NUM_TLB_SET_WAYS-1];

    assign stg_tlb_rdata[2] = tlb_rdata;

    always_ff @(posedge clk)
    begin
        for (int s = 2; s < NUM_TLB_LOOKUP_PIPE_STAGES; s = s + 1)
        begin
            stg_tlb_rdata[s + 1] <= stg_tlb_rdata[s];
        end
    end


    //
    // Stage 0: read from TLB
    //

    // Set read address for lookup
    assign tlb_addr[0] = t_TLB_IDX'(lookupPageVA[0]);


    //
    // Stage 1: nothing -- waiting for two cycle registered TLB response
    //


    //
    // Stage 2: First half of tag comparison
    //

    //
    // Process response from TLB block RAM.  Is the requested VA
    // in the TLB or does it need to be retrieved from the page table?
    //

    // The bit reduction of tag comparision is too involved to complete
    // in a single cycle at the desired frequency.  This register holds
    // the first stage of comparison, with each way's comparison reduced
    // to as a a bitwise XOR. The consuming stage must simply NOR the bits
    // together.
    t_TLB_VIRTUAL_TAG stg3_xor_tag[0 : 1][NUM_TLB_SET_WAYS-1 : 0];

    always_ff @(posedge clk)
    begin
        for (int p = 0; p < 2; p = p + 1)
        begin
            // Look for a match in each of the ways in the TLB set
            for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
            begin
                // Partial comparion of tags this stage.  The remainder
                // of the bit reduction will complete in the next cycle.
                stg3_xor_tag[p][way] <=
                    stg_tlb_rdata[2][p][way].tag ^ target_tlb_tag(2, p);
            end
        end
    end


    //
    // Stage 3: Complete tag comparison
    //

    // Record whether there was a lookup miss.  The result will be
    // consumed by the miss handler in a later section below.
    logic lookup_page_miss[0 : 1];

    // Tag comparison.
    logic [NUM_TLB_SET_WAYS-1 : 0] lookup_way_hit_vec[0 : 1];
    logic [$clog2(NUM_TLB_SET_WAYS)-1 : 0] lookup_way_hit[0 : 1];

    //
    // Reduce previous stage's XOR tag matching to a single bit
    //
    always_ff @(posedge clk)
    begin
        for (int p = 0; p < 2; p = p + 1)
        begin
            for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
            begin
                // Last cycle did a partial comparison, leaving multiple
                // bits per way that all must be 1 for a match.
                lookup_way_hit_vec[p][way] <=
                    stg_state[3][p].did_lookup && ~ (|(stg3_xor_tag[p][way]));
            end
        end
    end


    //
    // Final stage, follows tag comparison
    //

    always_comb
    begin
        // Set result for both ports (one for reads one for writes)
        for (int p = 0; p < 2; p = p + 1)
        begin
            // Lookup is valid if some way hit
            lookupValid[p] = |(lookup_way_hit_vec[p]);

            // Flag misses.
            lookup_page_miss[p] = stg_state[4][p].did_lookup && ! lookupValid[p];

            // Get the physical page index from the chosen way
            lookupRspPagePA[p] = 'x;
            for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
            begin
                if (lookup_way_hit_vec[p][way])
                begin
                    // Valid way
                    lookup_way_hit[p] = way;

                    // Get the physical page index
                    lookupRspPagePA[p] = stg_tlb_rdata[4][p][way].idx;
                    break;
                end
            end

        end
    end


    // ====================================================================
    //
    //   TLB miss handler.
    //
    // ====================================================================

    typedef enum logic [3:0]
    {
        STATE_TLB_IDLE,
        STATE_TLB_READ_REQ,
        STATE_TLB_READ_RSP,
        STATE_TLB_SEARCH_LINE,
        STATE_TLB_REQ_LRU,
        STATE_TLB_RECV_LRU,
        STATE_TLB_PTE_MATCH,
        STATE_TLB_BUBBLE,
        STATE_TLB_ERROR
    }
    t_STATE_TLB;

    t_STATE_TLB state;

    // Bytes to hold a single PTE
    localparam PTE_BYTES = (CCI_PT_VA_TAG_BITS + CCI_PT_PA_IDX_BITS + 7) / 8;
    // Bytes to hold a page table pointer
    localparam PT_IDX_BYTES = (CCI_PT_PA_IDX_BITS + 7) / 8;
    // Number of page table entries in a line
    localparam PTES_PER_LINE = ((CCI_CLDATA_WIDTH / 8) - PT_IDX_BYTES) / PTE_BYTES;

    // Buffer for storing the line being searched in the page table
    t_cci_clData pt_line;
    // Counter to track number of PTEs active in pt_line
    logic [PTES_PER_LINE : 0] pte_num;

    // One page table entry
    typedef struct packed
    {
        t_PTE_VA_TAG       vTag;
        t_TLB_PHYSICAL_IDX pIdx;
    }
    t_PTE;

    t_PTE found_pte;
    t_PTE cur_pte;
    assign cur_pte = t_PTE'(pt_line);

    t_PTE_VA_HASH_IDX pte_hash_idx;
    t_PTE_VA_HASH_IDX pte_hash_idx_vec[0 : 1];

    t_PTE_VA_TAG pte_va_tag;
    t_PTE_VA_TAG pte_va_tag_vec[0 : 1];

    t_PTE_IDX pte_idx[0 : 1];

    // Bubble state held for two cycles -- see STATE_TLB_BUBBLE handler.
    logic [1:0] bubble_hold;

    // Miss channel arbiter -- used for fairness
    logic last_miss_channel;

    logic lru_rdy;
    logic lru_lookup_rsp_rdy;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_TLB_IDLE;
            last_miss_channel <= 1'b0;
            bubble_hold <= 1'b1;
        end
        else
        begin
            case (state)
              STATE_TLB_IDLE:
                begin
                    //
                    // Did one of the channels miss?  Use the last_miss_channel
                    // arbiter to alternate between channels.
                    //
                    if (lookup_page_miss[0] &&
                        ((last_miss_channel == 1) || ! lookup_page_miss[1]))
                    begin
                        last_miss_channel <= 0;

                        if (DEBUG_MESSAGES)
                        begin
                            $display("TLB: Lookup for miss chan 0, VA 0x%x",
                                     {stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][0].lookup_page_va, CCI_PT_PAGE_OFFSET_BITS'(0)});
                        end
                    end
                    else
                    begin
                        last_miss_channel <= 1;

                        if (DEBUG_MESSAGES && lookup_page_miss[1])
                        begin
                            $display("TLB: Lookup for miss chan 1, VA 0x%x",
                                     {stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][1].lookup_page_va, CCI_PT_PAGE_OFFSET_BITS'(0)});
                        end
                    end

                    if (lookup_page_miss[0] || lookup_page_miss[1])
                    begin
                        state <= STATE_TLB_READ_REQ;
                    end

                    //
                    // Unconditionally record the index in the hash table in
                    // case of a TLB miss.  We could do this conditionally, above,
                    // but that adds unnecessary logic to a critical path.
                    //

                    for (int c = 0; c < 2; c = c + 1)
                    begin
                        {pte_va_tag_vec[c], pte_hash_idx_vec[c]} <=
                            stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][c].lookup_page_va;

                        // Why the double application of types to lookup_page_va?
                        // The hash index isolates the proper bits of the page
                        // address in the hash table.  The PTE index type grows
                        // the pointer to the full size index used in the PTE.
                        // (The PTE index space includes both the hash table
                        // and overflow space to which hash entries can point
                        // in order to construct longer linked lists.)
                        pte_idx[c] <=
                            t_PTE_IDX'(t_PTE_VA_HASH_IDX'(stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][c].lookup_page_va));
                    end
                end

              STATE_TLB_READ_REQ:
                begin
                    //
                    // Request a line from the page table.
                    //
                    if (tlbReadIdxRdy)
                    begin
                        state <= STATE_TLB_READ_RSP;
                    end

                    pte_va_tag <= pte_va_tag_vec[last_miss_channel];
                    pte_hash_idx <= pte_hash_idx_vec[last_miss_channel];
                end

              STATE_TLB_READ_RSP:
                begin
                    //
                    // Wait for page table line read response.
                    //
                    pt_line <= tlbReadData;
                    pte_num <= PTES_PER_LINE;

                    if (tlbReadDataEn)
                    begin
                        state <= STATE_TLB_SEARCH_LINE;
                    end
                end

              STATE_TLB_SEARCH_LINE:
                begin
                    //
                    // Iterate over the PTEs in a page table line, looking
                    // for a VA tag match.
                    //
                    if (pte_num == PTES_PER_LINE'(0))
                    begin
                        // Last PTE in the current line.  Continue along
                        // the linked list of lines.
                        if (t_PTE_IDX'(pt_line) == t_PTE_IDX'(0))
                        begin
                            // End of list
                            state <= STATE_TLB_ERROR;

                            if (DEBUG_MESSAGES)
                            begin
                                $display("TLB: ERROR, failed to find 0x%x",
                                         {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)});
                            end
                        end
                        else
                        begin
                            // Read the next line in the linked list
                            state <= STATE_TLB_READ_REQ;

                            if (DEBUG_MESSAGES)
                            begin
                                $display("TLB: Search for 0x%x, next line %0d",
                                         {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                         t_PTE_IDX'(pt_line));
                            end
                        end
                    end
                    else if (cur_pte.vTag == pte_va_tag)
                    begin
                        // Found the requested PTE!
                        state <= STATE_TLB_REQ_LRU;

                        if (DEBUG_MESSAGES)
                        begin
                            $display("TLB: Found 0x%x (PA 0x%x), num %0d",
                                     {cur_pte.vTag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.pIdx, CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     pte_num);
                        end
                    end
                    else
                    begin
                        if (cur_pte.vTag == t_PTE_VA_TAG'(0))
                        begin
                            // NULL VA tag -- no more translations
                            state <= STATE_TLB_ERROR;
                        end

                        if (DEBUG_MESSAGES)
                        begin
                            $display("TLB: Search for 0x%x, at 0x%x (PA 0x%x), num %0d",
                                     {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.vTag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.pIdx, CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     pte_num);
                        end
                    end

                    // Record the found PTE unconditionally.  It will only be
                    // used after transition to STATE_TLB_REQ_LRU.
                    found_pte <= cur_pte;

                    // Shift the line by one PTE so the next iteration
                    // may search the next PTE.  The size of a PTE is
                    // rounded up to a multiple of bytes.  This only matters
                    // when the state remains STATE_TLB_SEARCH_LINE.
                    pt_line <= pt_line >> (8 * (($bits(t_PTE) + 7) / 8));
                    pte_num <= pte_num - 1;

                    // Unconditionally update pte_idx in case a new PTE entry
                    // must be read from host memory. This will only be used
                    // if the state changes back to STATE_TLB_READ_REQ in the
                    // code above.
                    pte_idx[0] <= t_PTE_IDX'(pt_line);
                    pte_idx[1] <= t_PTE_IDX'(pt_line);
                end

              STATE_TLB_REQ_LRU:
                begin
                    // Request LRU state to pick a victim
                    if (lru_rdy)
                    begin
                        state <= STATE_TLB_RECV_LRU;
                    end
                end

              STATE_TLB_RECV_LRU:
                begin
                    // Receive the response from the LRU lookup
                    if (lru_lookup_rsp_rdy)
                    begin
                        state <= STATE_TLB_PTE_MATCH;
                    end
                end

              STATE_TLB_PTE_MATCH:
                begin
                    // The translation is added to the TLB (using
                    // combinational logic below).
                    state <= STATE_TLB_BUBBLE;
                end

              STATE_TLB_BUBBLE:
                begin
                    // Bubble cycles guarantee the TLB is updated before
                    // another miss may be triggered for the same page.
                    // Hold for two cycles.
                    bubble_hold <= bubble_hold + 1;
                    if (bubble_hold == 0)
                    begin
                        state <= STATE_TLB_IDLE;
                    end
                end

              STATE_TLB_ERROR:
                begin
                    // Terminal -- failed to find translation for a VA.
                end
            endcase
        end
    end

    // Request a page table read depending on state.
    assign tlbReadIdx = pte_idx[last_miss_channel];
    assign tlbReadIdxEn = tlbReadIdxRdy && (state == STATE_TLB_READ_REQ);

    // Signal an error
    assign lookupNotPresent[0] = (state == STATE_TLB_ERROR) &&
                                 (last_miss_channel == 0);
    assign lookupNotPresent[1] = (state == STATE_TLB_ERROR) &&
                                 (last_miss_channel == 1);

    //
    // TLB insertion (in STATE_TLB_PTE_MATCH)
    //

    // Convert from page table tag/hash to TLB tag/index
    t_TLB_IDX insert_idx;
    t_TLB_VIRTUAL_TAG insert_tag;
    assign {insert_tag, insert_idx} = {pte_va_tag, pte_hash_idx};


    // ====================================================================
    //
    //   Manage access to TLB port 0.
    //
    // ====================================================================

    // Port 0 is trivial since there is no contention on on TLB port 0.
    // Only the lookup function reads from it and there is no writer
    // connected to the port.
    assign lookupRdy[0] = initialized;


    // ====================================================================
    //
    //   Manage access to TLB port 1.
    //
    // ====================================================================

    // Port 1 is used for updates in addition to lookups.
    assign lookupRdy[1] = initialized && (state != STATE_TLB_PTE_MATCH);

    // LRU replacement.  Determine which way to replace when inserting
    // a new translation in the TLB.
    logic [NUM_TLB_SET_WAYS-1 : 0] lru_repl_vec;

    always_comb
    begin
        if (! initialized)
        begin
            // Initialization loop
            tlb_wdata.tag = 0;
            tlb_wdata.idx = 'x;
        end
        else
        begin
            // TLB update -- write virtual address TAG and physical page index.
            tlb_wdata.tag = insert_tag;
            tlb_wdata.idx = found_pte.pIdx;
        end

        // Pick the LRU way when writing.  This happens only during
        // initialization and when a new translation is being added to
        // the TLB:  state == STATE_TLB_PTE_MATCH.
        for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
        begin
            tlb_wen[way] = ! initialized ||
                           ((state == STATE_TLB_PTE_MATCH) &&
                            lru_repl_vec[way]);
        end

        // Address is the update address if writing and the read address
        // otherwise.
        if (! initialized)
        begin
            tlb_addr[1] = t_TLB_IDX'(init_idx);
        end
        else if (state == STATE_TLB_PTE_MATCH)
        begin
            tlb_addr[1] = t_TLB_IDX'(insert_idx);
        end
        else
        begin
            tlb_addr[1] = t_TLB_IDX'(lookupPageVA[1]);
        end
    end

    always_ff @(posedge clk)
    begin
        if (initialized && DEBUG_MESSAGES)
        begin
            for (int p = 0; p < 2; p = p + 1)
            begin
                if (lookupEn[p])
                begin
                    $display("TLB: Lookup chan %0d, VA 0x%x",
                             p,
                             {lookupPageVA[p], CCI_PT_PAGE_OFFSET_BITS'(0)});
                end

                if (lookupValid[p])
                begin
                    $display("TLB: Hit chan %0d, idx %0d, way %0d, PA 0x%x",
                             p, target_tlb_idx(NUM_TLB_LOOKUP_PIPE_STAGES, p),
                             lookup_way_hit[p],
                             {lookupRspPagePA[p], CCI_PT_PAGE_OFFSET_BITS'(0)});
                end
            end

            if (state == STATE_TLB_PTE_MATCH)
            begin
                for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
                begin
                    if (tlb_wen[way])
                    begin
                        $display("TLB: Insert idx %0d, way %0d, VA 0x%x, PA 0x%x",
                                 tlb_addr[1], way,
                                 {tlb_wdata.tag, tlb_addr[1], CCI_PT_PAGE_OFFSET_BITS'(0)},
                                 {tlb_wdata.idx, CCI_PT_PAGE_OFFSET_BITS'(0)});
                    end
                end
            end

            if (tlbReadIdxEn)
                $display("PTE read idx 0x%x", tlbReadIdx);
        end
    end


    // ====================================================================
    //
    //   LRU table for picking victim during TLB insertion.
    //
    // ====================================================================

    // Do a lookup in STATE_TLB_REQ_LRU
    logic lru_lookup_en;
    assign lru_lookup_en = (state == STATE_TLB_REQ_LRU);

    // Register the response when it arrives
    logic [NUM_TLB_SET_WAYS-1 : 0] lru_lookup_vec_rsp;
    always_ff @(posedge clk)
    begin
        if (lru_lookup_rsp_rdy)
        begin
            lru_repl_vec <= lru_lookup_vec_rsp;
        end
    end

    cci_mpf_prim_lru_pseudo
      #(
        .N_WAYS(NUM_TLB_SET_WAYS),
        .N_ENTRIES(NUM_TLB_SETS)
        )
      lru
        (
         .clk,
         .reset,
         .rdy(lru_rdy),
         .lookupIdx(insert_idx),
         .lookupEn(lru_lookup_en),
         .lookupVecRsp(lru_lookup_vec_rsp),
         .lookupRsp(),
         .lookupRspRdy(lru_lookup_rsp_rdy),
         .refIdx0(target_tlb_idx(NUM_TLB_LOOKUP_PIPE_STAGES, 1)),
         .refWayVec0(lookup_way_hit_vec[0]),
         .refEn0(lookupValid[0]),
         .refIdx1(target_tlb_idx(NUM_TLB_LOOKUP_PIPE_STAGES, 1)),
         .refWayVec1(lookup_way_hit_vec[1]),
         .refEn1(lookupValid[1])
         );

endmodule // cci_mpf_shim_vtp_assoc
