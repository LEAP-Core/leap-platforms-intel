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

    logic reset_n;
    assign reset_n = fiu.reset_n;


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

    assign afu_buf.reset_n = fiu.reset_n;

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

        if (reset_n)
        begin
            assert((afu_buf.c0Tx.hdr[RESERVED_MDATA_IDX] == 0) ||
                   ! afu_buf.c0Tx.rdValid) else
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
        input t_cci_mpf_cl_vaddr addr;

        return addr[$high(addr) : LINE_PAGE_OFFSET_BITS];
    endfunction

    // Given the virtual address of a line return the offset of the line from
    // the containing page.
    function automatic t_VA_PAGE_OFFSET pageOffsetFromVA;
        input t_cci_mpf_cl_vaddr addr;

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
    t_cci_cldata tlbReadData;
    logic tlbReadDataEn;

    cci_mpf_shim_vtp_assoc
      tlb
        (
         .clk,
         .reset_n,
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
        if (reset_n)
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
    localparam AFU_PIPE_LAST_STAGE = 2;
    t_if_cci_mpf_c0_Tx c0_afu_pipe[0 : AFU_PIPE_LAST_STAGE];
    t_if_cci_mpf_c1_Tx c1_afu_pipe[0 : AFU_PIPE_LAST_STAGE];


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
        (lookupValid[0] || ! cci_mpf_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
        ! fiu.c0TxAlmFull &&
        ! tlbReadIdxEn;

    logic c1_fwd_req;
    assign c1_fwd_req =
        c1_request_rdy &&
        (lookupValid[1] ||
         c1_afu_pipe[AFU_PIPE_LAST_STAGE].intrValid ||
         ! cci_mpf_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
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

    // Pass new requests to the afu_pipe?  Old retries have priority over
    // new requests.
    assign deqC0Tx = c0_new_req && ! c0_retry_req;
    assign deqC1Tx = c1_new_req && ! c1_retry_req;


    //
    // Advance the pipeline
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            for (int i = 0; i <= AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i] <= cci_mpf_c0TxClearValids();
                c1_afu_pipe[i] <= cci_mpf_c1TxClearValids();
            end
        end
        else
        begin
            // All but first stage is a simple systolic pipeline
            for (int i = 0; i < AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i+1] <= c0_afu_pipe[i];
                c1_afu_pipe[i+1] <= c1_afu_pipe[i];
            end

            // What goes in stage 0 of the pipeline?
            if (c0_retry_req)
            begin
                // Oldest request either failed translation or couldn't
                // be forwarded due to contention.
                c0_afu_pipe[0] <= c0_afu_pipe[AFU_PIPE_LAST_STAGE];
            end
            else
            begin
                c0_afu_pipe[0] <= afu_buf.c0Tx;
            end

            if (c1_retry_req)
            begin
                c1_afu_pipe[0] <= c1_afu_pipe[AFU_PIPE_LAST_STAGE];
            end
            else
            begin
                c1_afu_pipe[0] <= afu_buf.c1Tx;
            end
        end
    end


    //
    // Tap afu_pipe to request translation from the TLB.  Translation is
    // skipped if the incoming request already has a physical address.
    //
    assign lookupPageVA[0] =
        pageFromVA(cci_mpf_getReqVAddr(c0_afu_pipe[AFU_PIPE_LAST_STAGE-2].hdr));
    assign lookupEn[0] =
        lookupRdy[0] &&
        c0_afu_pipe[AFU_PIPE_LAST_STAGE-2].rdValid &&
        cci_mpf_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LAST_STAGE-2].hdr);

    assign lookupPageVA[1] =
        pageFromVA(cci_mpf_getReqVAddr(c1_afu_pipe[AFU_PIPE_LAST_STAGE-2].hdr));
    assign lookupEn[1] =
        lookupRdy[1] &&
        c1_afu_pipe[AFU_PIPE_LAST_STAGE-2].wrValid &&
        cci_mpf_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LAST_STAGE-2].hdr);


    // ====================================================================
    //
    //  Requests
    //
    // ====================================================================

    // Construct the read request header.
    t_cci_mpf_ReqMemHdr c0_req_hdr;

    // Base address of the page table
    t_cci_cl_paddr page_table_base;
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
            if (cci_mpf_getReqAddrIsVirtual(c0_req_hdr))
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
            c0_req_hdr = cci_mpf_genReqHdr(eREQ_RDLINE_S,
                                           t_cci_mpf_cl_vaddr'(page_table_base + tlbReadIdx),
                                           t_cci_mdata'(0),
                                           cci_mpf_defaultReqHdrParams(0));

            // Tag the request as a local page table walk
            c0_req_hdr[RESERVED_MDATA_IDX] = 1'b1;
        end
    end

    // Channel 0 (read) is either client requests or reads for TLB misses
    assign fiu.c0Tx = cci_mpf_genC0TxReadReq(c0_req_hdr, c0_fwd_req || tlbReadIdxEn);

    // Channel 1 request logic
    t_cci_mpf_ReqMemHdr c1_req_hdr;
    t_VA_PAGE_OFFSET c1_req_offset;

    always_comb
    begin
        c1_req_hdr = c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr;

        // Request's line offset within the page.
        c1_req_offset = pageOffsetFromVA(c1_req_hdr.base.address);

        // Replace the address with the physical address
        if (cci_mpf_getReqAddrIsVirtual(c1_req_hdr))
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

        // Is the header rewritten for a virtually address write?
        if (c1_afu_pipe[AFU_PIPE_LAST_STAGE].wrValid)
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

        // Only forward client-generated read responses
        afu_buf.c0Rx.rdValid = fiu.c0Rx.rdValid && ! is_pt_rsp;

        // Connect read responses to the TLB management code
        tlbReadData = fiu.c0Rx.data;
        tlbReadDataEn = fiu.c0Rx.rdValid && is_pt_rsp;

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
    input  logic reset_n,

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
    input t_cci_cldata tlbReadData,
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
        assert (CCI_MPF_CL_VADDR_WIDTH + $clog2(CCI_CLDATA_WIDTH >> 3) ==
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
    // other registered signals.  The register is tagged "keep" because
    // fit would otherwise merge the next register stage into the
    // block RAM logic, which has been causing timing problems.
    t_TLB_ENTRY tlb_rdata_q[0 : 1][0 : NUM_TLB_SET_WAYS-1] /* synthesis keep */;
    t_TLB_ENTRY tlb_rdata_qq[0 : 1][0 : NUM_TLB_SET_WAYS-1];

    genvar w;
    generate
        for (w = 0; w < NUM_TLB_SET_WAYS; w = w + 1)
        begin: gen_tlb
            cci_mpf_prim_dualport_ram
              #(
                .N_ENTRIES(NUM_TLB_SETS),
                .N_DATA_BITS($bits(t_TLB_ENTRY))
                )
              tlb(.clk0(clk),
                  .addr0(tlb_addr[0]),
                  .wen0(1'b0),
                  .wdata0('x),
                  .rdata0(tlb_rdata_q[0][w]),
                  .clk1(clk),
                  .addr1(tlb_addr[1]),
                  .wen1(tlb_wen[w]),
                  .wdata1(tlb_wdata),
                  .rdata1(tlb_rdata_q[1][w])
                  );
        end
    endgenerate

    // Register block RAM output for timing
    always_ff @(posedge clk)
    begin
        for (int p = 0; p < 2; p = p + 1)
        begin
            for (int w = 0; w < NUM_TLB_SET_WAYS; w = w + 1)
            begin
                tlb_rdata_qq[p][w] <= tlb_rdata_q[p][w];
            end
        end
    end


    //
    // Initialize the TLB.  The actual write will happen in a rule later
    // that arbitrates among read and write requests for port 1.
    //
    logic [$bits(t_TLB_IDX) : 0] init_idx;
    logic initialized;
    assign initialized = init_idx[$high(init_idx)];

    always_ff @(posedge clk)
    begin
        if (! reset_n)
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
    //   Match tag to TLB reads and return match details to the client.
    //
    // ====================================================================

    // Set read address for lookup
    assign tlb_addr[0] = t_TLB_IDX'(lookupPageVA[0]);

    //
    // Does a tag read from the TLB match a request?
    //
    logic did_lookup_q[0 : 1];
    logic did_lookup_qq[0 : 1];
    logic [$bits(lookupPageVA)-1 : 0] lookup_page_va_q[0 : 1];
    logic [$bits(lookupPageVA)-1 : 0] lookup_page_va_qq[0 : 1];

    // Record whether there was a lookup miss.  The result will be
    // consumed by the miss handler in a later section below.
    logic lookup_page_miss[0 : 1];

    t_TLB_IDX test_idx[0 : 1];
    t_TLB_VIRTUAL_TAG test_tag[0 : 1];

    // LRU update
    logic [NUM_TLB_SET_WAYS-1 : 0] lookup_way_hit_vec[0 : 1];
    logic [$clog2(NUM_TLB_SET_WAYS)-1 : 0] lookup_way_hit[0 : 1];

    //
    // Process response from TLB block RAM.  Is the requested VA
    // in the TLB or does it need to be retrieved from the page table?
    //
    always_comb
    begin
        // Set result for both ports (one for reads one for writes)
        for (int p = 0; p < 2; p = p + 1)
        begin
            lookupRspPagePA[p] = 'x;
            lookupValid[p] = 0;

            // Convert virtual page address being checked to a tag
            // and TLB set index.
            {test_tag[p], test_idx[p]} = lookup_page_va_qq[p];

            lookup_way_hit_vec[p] = NUM_TLB_SET_WAYS'(0);

            // Look for a match in each of the ways in the TLB set
            for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
            begin
                if (tlb_rdata_qq[p][way].tag == test_tag[p])
                begin
                    // Valid!
                    lookupRspPagePA[p] = tlb_rdata_qq[p][way].idx;
                    lookupValid[p] = did_lookup_qq[p];

                    lookup_way_hit_vec[p][way] = 1'b1;
                    lookup_way_hit[p] = way;
                    break;
                end
            end

            // Flag misses.
            lookup_page_miss[p] = did_lookup_qq[p] && ! lookupValid[p];
        end
    end

    //
    // Record details of TLB read request for use when the read data
    // is available from the block RAM.
    //
    always_ff @(posedge clk)
    begin
        for (int p = 0; p < 2; p = p + 1)
        begin
            lookup_page_va_q[p] <= lookupPageVA[p];
            lookup_page_va_qq[p] <= lookup_page_va_q[p];

            if (! reset_n)
            begin
                did_lookup_q[p] <= 0;
                did_lookup_qq[p] <= 0;
            end
            else
            begin
                // Was there a lookup requested on this port?  Result
                // comes from the block RAM next cycle.
                did_lookup_q[p] <= lookupEn[p];
                did_lookup_qq[p] <= did_lookup_q[p];
            end 
        end
    end


    // ====================================================================
    //
    //   TLB miss handler.
    //
    // ====================================================================

    typedef enum logic [2:0]
    {
        STATE_TLB_IDLE,
        STATE_TLB_READ_REQ,
        STATE_TLB_READ_RSP,
        STATE_TLB_SEARCH_LINE,
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
    t_cci_cldata pt_line;
    // Counter to track number of PTEs active in pt_line
    logic [PTES_PER_LINE : 0] pte_num;

    // One page table entry
    typedef struct packed
    {
        t_PTE_VA_TAG       vTag;
        t_TLB_PHYSICAL_IDX pIdx;
    }
    t_PTE;

    t_PTE cur_pte;
    assign cur_pte = t_PTE'(pt_line);

    t_PTE_VA_HASH_IDX pte_hash_idx;
    t_PTE_VA_TAG pte_va_tag;
    t_PTE_IDX pte_idx;

    // Miss channel arbiter -- used for fairness
    logic last_miss_channel;

    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            state <= STATE_TLB_IDLE;
            last_miss_channel <= 0;
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
                        {pte_va_tag, pte_hash_idx} <= lookup_page_va_qq[0];
                        // The hash table is in the early part of page table
                        // memory. There is overflow space in the page table
                        // beyond the hashes, so a page table line index is
                        // larger than a hash table index.
                        pte_idx <= t_PTE_IDX'(t_PTE_VA_HASH_IDX'(lookup_page_va_qq[0]));
                        last_miss_channel <= 0;
                    end
                    else if (lookup_page_miss[1])
                    begin
                        {pte_va_tag, pte_hash_idx} <= lookup_page_va_qq[1];
                        pte_idx <= t_PTE_IDX'(t_PTE_VA_HASH_IDX'(lookup_page_va_qq[1]));
                        last_miss_channel <= 1;
                    end

                    if (lookup_page_miss[0] || lookup_page_miss[1])
                    begin
                        state <= STATE_TLB_READ_REQ;
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

                        pte_idx <= t_PTE_IDX'(pt_line);
                    end
                    else if (cur_pte.vTag == pte_va_tag)
                    begin
                        // Found the requested PTE!
                        state <= STATE_TLB_PTE_MATCH;

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

                        // Shift the line by one PTE so the next iteration
                        // may search the next PTE.  The size of a PTE is
                        // rounded up to a multiple of bytes.
                        pt_line = pt_line >> (8 * (($bits(t_PTE) + 7) / 8));
                    end

                    pte_num = pte_num - 1;
                end

              STATE_TLB_PTE_MATCH:
                begin
                    // The translation is added to the TLB (using
                    // combinational logic below).
                    state <= STATE_TLB_BUBBLE;
                end

              STATE_TLB_BUBBLE:
                begin
                    // Bubble cycle guarantees the TLB is updated before
                    // another miss may be triggered for the same page.
                    state <= STATE_TLB_IDLE;
                end

              STATE_TLB_ERROR:
                begin
                    // Terminal -- failed to find translation for a VA.
                end
            endcase
        end
    end

    // Request a page table read depending on state.
    assign tlbReadIdx = pte_idx;
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

    // LRU replacement
    logic [NUM_TLB_SET_WAYS-1 : 0] lru_lookup_vec_rsp;

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
            tlb_wdata.idx = cur_pte.pIdx;
        end

        // Pick the LRU way
        for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
        begin
            tlb_wen[way] = ! initialized ||
                           ((state == STATE_TLB_PTE_MATCH) &&
                            lru_lookup_vec_rsp[way]);
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
                             p, test_idx[p], lookup_way_hit[p],
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

    // Look up LRU when making the transition to STATE_TLB_PTE_MATCH.
    logic lru_lookup_en;
    assign lru_lookup_en = (state == STATE_TLB_SEARCH_LINE) &&
                           (pte_num != PTES_PER_LINE'(0)) &&
                           (cur_pte.vTag == pte_va_tag);

    cci_mpf_prim_lru_pseudo
      #(
        .N_WAYS(NUM_TLB_SET_WAYS),
        .N_ENTRIES(NUM_TLB_SETS)
        )
      lru
        (
         .clk,
         .reset_n,
         .rdy(),
         .lookupIdx(insert_idx),
         .lookupEn(lru_lookup_en),
         .lookupVecRsp(lru_lookup_vec_rsp),
         .lookupRsp(),
         .refIdx0(test_idx[0]),
         .refWayVec0(lookup_way_hit_vec[0]),
         .refEn0(lookupValid[0]),
         .refIdx1(test_idx[1]),
         .refWayVec1(lookup_way_hit_vec[1]),
         .refEn1(lookupValid[1])
         );

endmodule // cci_mpf_shim_vtp_assoc
