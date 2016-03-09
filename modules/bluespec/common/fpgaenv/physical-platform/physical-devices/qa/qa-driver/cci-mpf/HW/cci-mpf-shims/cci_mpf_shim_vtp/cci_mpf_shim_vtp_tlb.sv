//
// Copyright (c) 2016, Intel Corporation
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

`include "cci_mpf_shim_vtp.vh"


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
module cci_mpf_shim_vtp_tlb
  #(
    // Number of offset bits in pages managed by this TLB instance.  OFFSETS
    // ARE LINES, NOT BYTES.  Typical values are 6 for 4KB pages and 15
    // for 2MB pages.
    parameter CCI_PT_PAGE_OFFSET_BITS = CCI_PT_2MB_PAGE_OFFSET_BITS,

    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    cci_mpf_shim_vtp_tlb_if.server tlb_if
    );

    // The TLB is associative.  Define the width of a set.
    localparam NUM_TLB_SET_WAYS = 4;

    // Number of sets in the FPGA-side TLB
    localparam NUM_TLB_SETS = 1024;
    localparam NUM_TLB_INDEX_BITS = $clog2(NUM_TLB_SETS);
    typedef logic [NUM_TLB_INDEX_BITS-1 : 0] t_tlb_idx;


    // ====================================================================
    //
    // The page size managed in this TLB is configured by setting the
    // CCI_PT_PAGE_OFFSET_BITS parameter.  Build types around the
    // configured size and functions to map to/from 4KB page indices
    // used in cci_mpf_shim_vtp_tlb_if.
    //
    // The interface connecting the TLB to the VTP pipeline and to the
    // page walker always uses 4KB aligned addresses, independent of
    // the page size managed in a TLB instance.
    //
    // ====================================================================

    localparam CCI_PT_VA_PAGE_INDEX_BITS = CCI_PT_VA_BITS -
                                           CCI_PT_PAGE_OFFSET_BITS;
    localparam CCI_PT_PA_PAGE_INDEX_BITS = CCI_PT_PA_BITS -
                                           CCI_PT_PAGE_OFFSET_BITS;

    typedef logic [CCI_PT_VA_PAGE_INDEX_BITS-1 : 0] t_tlb_va_page_idx;
    typedef logic [CCI_PT_PA_PAGE_INDEX_BITS-1 : 0] t_tlb_pa_page_idx;

    // Convert 4KB page index to this TLB's size. We assume the index
    // is properly aligned.
    function automatic t_tlb_va_page_idx tlbVAIdxFrom4K(t_tlb_4kb_va_page_idx p);
        return p[CCI_PT_4KB_VA_PAGE_INDEX_BITS - CCI_PT_VA_PAGE_INDEX_BITS +:
                 CCI_PT_VA_PAGE_INDEX_BITS];
    endfunction

    function automatic t_tlb_4kb_va_page_idx tlbVAIdxTo4K(t_tlb_va_page_idx p);
        t_tlb_4kb_va_page_idx p4k = CCI_PT_4KB_VA_PAGE_INDEX_BITS'(0);
        p4k[CCI_PT_4KB_VA_PAGE_INDEX_BITS-1 -: CCI_PT_VA_PAGE_INDEX_BITS] = p;
        return p4k;
    endfunction

    function automatic t_tlb_pa_page_idx tlbPAIdxFrom4K(t_tlb_4kb_pa_page_idx p);
        return p[CCI_PT_4KB_PA_PAGE_INDEX_BITS - CCI_PT_PA_PAGE_INDEX_BITS +:
                 CCI_PT_PA_PAGE_INDEX_BITS];
    endfunction

    function automatic t_tlb_4kb_pa_page_idx tlbPAIdxTo4K(t_tlb_pa_page_idx p);
        t_tlb_4kb_pa_page_idx p4k = CCI_PT_4KB_PA_PAGE_INDEX_BITS'(0);
        p4k[CCI_PT_4KB_PA_PAGE_INDEX_BITS-1 -: CCI_PT_PA_PAGE_INDEX_BITS] = p;
        return p4k;
    endfunction


    // A virtual address tag is the remainder of the address after using
    // the low bits as a direct-mapped index to a TLB set.  NOTE: The
    // FPGA-side TLB tag is a different size from the host-side page table
    // tag!  This is because the page table hash size is different from
    // the FPGA's TLB hash size.  The page table hash is large because
    // we can afford a large table in host memory.  The TLB here is in
    // block RAM so is necessarily smaller.
    localparam TLB_VA_TAG_BITS = CCI_PT_VA_PAGE_INDEX_BITS - NUM_TLB_INDEX_BITS;
    typedef logic [TLB_VA_TAG_BITS-1 : 0] t_tlb_virtual_tag;

    // A single TLB entry is a virtual tag and physical page index.
    typedef struct packed
    {
        t_tlb_virtual_tag tag;
        t_tlb_pa_page_idx idx;
    }
    t_tlb_entry;


    // ====================================================================
    //
    //  Storage for the TLB.  Each way is stored in a separate memory in
    //  order to permit updating a way without a read-modify-write.
    //
    // ====================================================================

    // The address and write data are broadcast to all ways in a set
    t_tlb_idx tlb_addr[0 : 1];

    // Write only uses port 1
    t_tlb_entry tlb_wdata;
    logic tlb_wen[0 : NUM_TLB_SET_WAYS-1];

    // Read response.  We label registers in this pipeline relative to
    // the head of the flow.  The data is returned from the block RAM in
    // the second cycle, so we label the output tlb_rdata_qq to match
    // other registered signals.
    t_tlb_entry tlb_rdata[0 : 1][0 : NUM_TLB_SET_WAYS-1];

    // Each way is ready at the same time since the init logic is the same
    logic tlb_rdy[0 : NUM_TLB_SET_WAYS-1];
    logic initialized;
    assign initialized = tlb_rdy[0];

    genvar w;
    generate
        for (w = 0; w < NUM_TLB_SET_WAYS; w = w + 1)
        begin: gen_tlb
            cci_mpf_prim_dualport_ram_init
              #(
                .N_ENTRIES(NUM_TLB_SETS),
                .N_DATA_BITS($bits(t_tlb_entry)),
                .N_OUTPUT_REG_STAGES(1)
                )
              tlb
               (
                .reset,
                .rdy(tlb_rdy[w]),

                .clk0(clk),
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
        t_tlb_va_page_idx lookup_page_va;
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
                stg_state[1][p].did_lookup <= tlb_if.lookupEn[p];
            end 

            stg_state[1][p].lookup_page_va <= tlbVAIdxFrom4K(tlb_if.lookupPageVA[p]);
        end

        for (int s = 1; s < NUM_TLB_LOOKUP_PIPE_STAGES; s = s + 1)
        begin
            stg_state[s + 1] <= stg_state[s];
        end
    end

    // Return target TLB index for VA
    function automatic t_tlb_idx target_tlb_idx(t_tlb_va_page_idx va);
        t_tlb_virtual_tag tag;
        t_tlb_idx idx;
        { tag, idx } = va;
        return idx;
    endfunction

    // Return target TLB tag for VA
    function automatic t_tlb_virtual_tag target_tlb_tag(t_tlb_va_page_idx va);
        t_tlb_virtual_tag tag;
        t_tlb_idx idx;
        { tag, idx } = va;
        return tag;
    endfunction

    //
    // TLB read response data arrives in stage 2.
    //
    t_tlb_entry stg_tlb_rdata[2 : NUM_TLB_LOOKUP_PIPE_STAGES][0 : 1][0 : NUM_TLB_SET_WAYS-1];

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
    assign tlb_addr[0] = t_tlb_idx'(tlbVAIdxFrom4K(tlb_if.lookupPageVA[0]));


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
    t_tlb_virtual_tag stg3_xor_tag[0 : 1][NUM_TLB_SET_WAYS-1 : 0];

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
                    stg_tlb_rdata[2][p][way].tag ^
                    target_tlb_tag(stg_state[2][p].lookup_page_va);
            end
        end
    end


    //
    // Stage 3: Complete tag comparison
    //

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
            tlb_if.lookupValid[p] = |(lookup_way_hit_vec[p]);

            // Flag misses.
            tlb_if.lookupMiss[p] = stg_state[4][p].did_lookup &&
                                   ! tlb_if.lookupValid[p];

            tlb_if.lookupMissVA[p] =
                tlbVAIdxTo4K(stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][p].lookup_page_va);

            // Get the physical page index from the chosen way
            tlb_if.lookupRspPagePA[p] = 'x;
            for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
            begin
                if (lookup_way_hit_vec[p][way])
                begin
                    // Valid way
                    lookup_way_hit[p] = way;

                    // Get the physical page index
                    tlb_if.lookupRspPagePA[p] =
                        tlbPAIdxTo4K(stg_tlb_rdata[4][p][way].idx);
                    break;
                end
            end

        end
    end


    // ====================================================================
    //
    //   Insertion logic for picking victim during TLB insertion.
    //
    // ====================================================================

    typedef enum logic [2:0]
    {
        STATE_TLB_FILL_IDLE,
        STATE_TLB_FILL_REQ_WAY,
        STATE_TLB_FILL_RECV_WAY,
        STATE_TLB_FILL_INSERT,
        STATE_TLB_FILL_BUBBLE
    }
    t_state_tlb_fill;

    t_state_tlb_fill fill_state;

    // Translation insertion request from page walker.
    assign tlb_if.fillRdy = (fill_state == STATE_TLB_FILL_IDLE);
    t_tlb_virtual_tag fill_tag;
    t_tlb_idx fill_idx;
    t_tlb_pa_page_idx fill_pa;

    logic repl_rdy;
    logic repl_lookup_rsp_rdy;

    logic [1:0] fill_bubble;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            fill_state <= STATE_TLB_FILL_IDLE;
            fill_bubble <= 1;
        end
        else
        begin
            case (fill_state)
              STATE_TLB_FILL_IDLE:
                begin
                    if (tlb_if.fillEn)
                    begin
                        fill_state <= STATE_TLB_FILL_REQ_WAY;

                        // Convert from VA to TLB tag/index
                        { fill_tag, fill_idx } <= tlbVAIdxFrom4K(tlb_if.fillVA);
                        fill_pa <= tlbPAIdxFrom4K(tlb_if.fillPA);
                    end
                end

              STATE_TLB_FILL_REQ_WAY:
                begin
                    if (repl_rdy)
                    begin
                        fill_state <= STATE_TLB_FILL_RECV_WAY;
                    end
                end

              STATE_TLB_FILL_RECV_WAY:
                begin
                    if (repl_lookup_rsp_rdy)
                    begin
                        fill_state <= STATE_TLB_FILL_INSERT;
                    end
                end

              STATE_TLB_FILL_INSERT:
                begin
                    fill_state <= STATE_TLB_FILL_BUBBLE;
                end

              STATE_TLB_FILL_BUBBLE:
                begin
                    // Bubble delays transition to IDLE to avoid repeated
                    // requests to the same miss VA.  Fills are only attempted
                    // when the state is idle.
                    fill_bubble <= fill_bubble + 1;
                    if (fill_bubble == 0)
                    begin
                        fill_state <= STATE_TLB_FILL_IDLE;
                    end
                end
            endcase
        end
    end

    // Do a lookup in STATE_TLB_FILL_REQ_WAY
    logic repl_lookup_en;
    assign repl_lookup_en = repl_rdy && (fill_state == STATE_TLB_FILL_REQ_WAY);

    // Replacement way selection.  Determine which way to replace when
    // inserting a new translation in the TLB.
    logic [NUM_TLB_SET_WAYS-1 : 0] way_repl_vec;
    logic [NUM_TLB_SET_WAYS-1 : 0] repl_lookup_vec_rsp;

    // Register the response when it arrives
    always_ff @(posedge clk)
    begin
        if (repl_lookup_rsp_rdy)
        begin
            way_repl_vec <= repl_lookup_vec_rsp;
        end
    end

    cci_mpf_prim_repl_random
      #(
        .N_WAYS(NUM_TLB_SET_WAYS),
        .N_ENTRIES(NUM_TLB_SETS)
        )
      repl
        (
         .clk,
         .reset,
         .rdy(repl_rdy),
         .lookupIdx(fill_idx),
         .lookupEn(repl_lookup_en),
         .lookupVecRsp(repl_lookup_vec_rsp),
         .lookupRsp(),
         .lookupRspRdy(repl_lookup_rsp_rdy),
         .refIdx0(target_tlb_idx(stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][0].lookup_page_va)),
         .refWayVec0(lookup_way_hit_vec[0]),
         .refEn0(tlb_if.lookupValid[0]),
         .refIdx1(target_tlb_idx(stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][1].lookup_page_va)),
         .refWayVec1(lookup_way_hit_vec[1]),
         .refEn1(tlb_if.lookupValid[1])
         );



    // ====================================================================
    //
    //   Manage access to TLB port 0.
    //
    // ====================================================================

    // Port 0 is trivial since there is no contention on on TLB port 0.
    // Only the lookup function reads from it and there is no writer
    // connected to the port.
    assign tlb_if.lookupRdy[0] = initialized;


    // ====================================================================
    //
    //   Manage access to TLB port 1.
    //
    // ====================================================================

    // Port 1 is used for updates in addition to lookups.
    assign tlb_if.lookupRdy[1] = initialized &&
                                 (fill_state != STATE_TLB_FILL_INSERT);

    always_comb
    begin
        // TLB update -- write virtual address TAG and physical page index.
        tlb_wdata.tag = fill_tag;
        tlb_wdata.idx = fill_pa;

        // Pick the victim way when writing.  This happens only during
        // initialization and when a new translation is being added to
        // the TLB: STATE_TLB_FILL_INSERT.
        for (int way = 0; way < NUM_TLB_SET_WAYS; way = way + 1)
        begin
            tlb_wen[way] = (fill_state == STATE_TLB_FILL_INSERT) &&
                           way_repl_vec[way];
        end

        // Address is the update address if writing and the read address
        // otherwise.
        if (fill_state == STATE_TLB_FILL_INSERT)
        begin
            tlb_addr[1] = t_tlb_idx'(fill_idx);
        end
        else
        begin
            tlb_addr[1] = t_tlb_idx'(tlbVAIdxFrom4K(tlb_if.lookupPageVA[1]));
        end
    end

    always_ff @(posedge clk)
    begin
        if (initialized && DEBUG_MESSAGES)
        begin
            for (int p = 0; p < 2; p = p + 1)
            begin
                if (tlb_if.lookupEn[p])
                begin
                    $display("TLB: Lookup chan %0d, VA 0x%x (line)",
                             p,
                             {tlb_if.lookupPageVA[p], CCI_PT_4KB_PAGE_OFFSET_BITS'(0)});
                end

                if (tlb_if.lookupValid[p])
                begin
                    $display("TLB: Hit chan %0d, idx %0d, way %0d, PA 0x%x",
                             p, target_tlb_idx(stg_state[NUM_TLB_LOOKUP_PIPE_STAGES][p].lookup_page_va),
                             lookup_way_hit[p],
                             {tlb_if.lookupRspPagePA[p], CCI_PT_4KB_PAGE_OFFSET_BITS'(0)});
                end
            end

            if (fill_state == STATE_TLB_FILL_INSERT)
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
        end
    end

endmodule // cci_mpf_shim_vtp_tlb

