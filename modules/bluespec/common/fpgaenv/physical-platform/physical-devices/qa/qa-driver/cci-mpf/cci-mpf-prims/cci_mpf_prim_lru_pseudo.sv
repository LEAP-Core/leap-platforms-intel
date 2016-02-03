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


//
// Pseudo LRU implementation.  Pseudo LRU sets a bit vector to 1 when an
// entry is referenced.  When all bits in a vector become 1 all bits are
// reset to 0.
//
// This implementation has more query and update ports than there are
// read and write ports in the internal memory.  Instead of blocking,
// the code makes a best effort to update the vector when requested.
// Lookup requests are always processed correctly.  The assumption is
// there are few lookups compared to updates and that sampling the
// updates instead of recording each one is sufficient.
//

module cci_mpf_prim_lru_pseudo
  #(
    parameter N_WAYS = 4,
    parameter N_ENTRIES = 1024
    )
   (
    input  logic clk,
    input  logic reset,

    // The entire module is ready after initialization.  Once ready, the
    // lookup function is always available.  The reference functions appear
    // always ready but make no guarantees that all references will be
    // recorded.  Contention on internal memory may require that some
    // references be ignored.
    output logic rdy,

    // Look up LRU for index
    input  logic [$clog2(N_ENTRIES)-1 : 0] lookupIdx,
    input  logic lookupEn,

    // Returns LRU one cycle after lookupEn.  The response is returned
    // in two forms with the same answer.  One is a one-hot vector.  The
    // other is an index.
    output logic [N_WAYS-1 : 0] lookupVecRsp,
    output logic [$clog2(N_WAYS)-1 : 0] lookupRsp,

    // Port 0 update.
    input  logic [$clog2(N_ENTRIES)-1 : 0] refIdx0,
    // Update refWayVec will be ORed into the current state
    input  logic [N_WAYS-1 : 0] refWayVec0,
    input  logic refEn0,

    // Port 1 update
    input  logic [$clog2(N_ENTRIES)-1 : 0] refIdx1,
    input  logic [N_WAYS-1 : 0] refWayVec1,
    input  logic refEn1
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_ENTRY_IDX;
    typedef logic [N_WAYS-1 : 0] t_WAY_VEC;


    //
    // Pseudo-LRU update function.
    //
    function automatic t_WAY_VEC updatePseudoLRU;
        input t_WAY_VEC cur;
        input t_WAY_VEC newLRU;

        // Or new LRU position into the current state
        t_WAY_VEC upd = cur | newLRU;

        // If all bits set turn everything off, otherwise return the updated
        // set.
        return (&(upd) == 1) ? t_WAY_VEC'(0) : upd;
    endfunction


    // ====================================================================
    //
    //   Storage
    //
    // ====================================================================

    t_ENTRY_IDX addr0;
    t_WAY_VEC wdata0;
    logic wen0;
    t_WAY_VEC rdata0;

    t_ENTRY_IDX addr1;
    t_WAY_VEC wdata1;
    logic wen1;
    t_WAY_VEC rdata1;

    cci_mpf_prim_dualport_ram
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS($bits(t_WAY_VEC))
        )
      lru_data
        (
         .clk0(clk),
         .addr0,
         .wen0,
         .wdata0,
         .rdata0,
         .clk1(clk),
         .addr1,
         .wen1,
         .wdata1,
         .rdata1
         );


    // ====================================================================
    //
    //   Initialization logic.  Port 0 will use it.
    //
    // ====================================================================

    logic [$clog2(N_ENTRIES) : 0] init_idx;
    logic initialized;
    assign initialized = init_idx[$high(init_idx)];
    assign rdy = initialized;

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
    //   LRU storage port 0 handles this module's port 0 updates and
    //   initialization.
    //
    // ====================================================================

    //
    // Update is a multi-cycle read/modify/write operation. An extra cycle
    // in the middle breaks the block RAM read response -> block RAM write
    // into separate cycles for timing.
    //
    logic update0_en;
    logic update0_en_q;
    logic update0_en_qq;

    t_ENTRY_IDX update0_idx;
    t_ENTRY_IDX update0_idx_q;
    t_ENTRY_IDX update0_idx_qq;

    // New reference
    t_WAY_VEC update0_ref;
    t_WAY_VEC update0_ref_q;
    t_WAY_VEC update0_ref_qq;

    // Current state into which new reference is added
    t_WAY_VEC update0_cur_lru_qq;

    //
    // Address and write data assignment.
    //
    always_comb
    begin
        // Default -- read for update if requested
        addr0 = refIdx0;
        wdata0 = 'x;
        wen0 = 1'b0;

        update0_en  = refEn0;
        update0_idx = refIdx0;
        update0_ref = refWayVec0;

        if (! initialized)
        begin
            // Initializing
            addr0 = t_ENTRY_IDX'(init_idx);
            wdata0 = t_WAY_VEC'(0);
            wen0 = 1'b1;

            // No new update can start since can't read for update
            update0_en = 1'b0;
        end
        else if (update0_en_qq)
        begin
            // Updating
            addr0 = update0_idx_qq;
            wdata0 = updatePseudoLRU(update0_cur_lru_qq, update0_ref_qq);
            wen0 = 1'b1;

            // No new update can start since can't read for update
            update0_en = 1'b0;
        end
    end

    // Read/modify/write update pipeline
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            update0_en_q <= 0;
            update0_en_qq <= 0;
        end
        else
        begin
            update0_en_q <= update0_en;
            update0_idx_q <= update0_idx;
            update0_ref_q <= update0_ref;

            // Register read response to avoid block RAM read response ->
            // block RAM write in a single cycle.
            update0_en_qq <= update0_en_q;
            update0_idx_qq <= update0_idx_q;
            update0_ref_qq <= update0_ref_q;
            update0_cur_lru_qq <= rdata0;
        end 
    end


    // ====================================================================
    //
    //   LRU storage port 1 handles this module's port 1 updates and
    //   LRU lookup requests.
    //
    // ====================================================================

    logic update1_en;
    logic update1_en_q;
    logic update1_en_qq;

    t_ENTRY_IDX update1_idx;
    t_ENTRY_IDX update1_idx_q;
    t_ENTRY_IDX update1_idx_qq;

    // New reference
    t_WAY_VEC update1_ref;
    t_WAY_VEC update1_ref_q;
    t_WAY_VEC update1_ref_qq;

    // Current state into which new reference is added
    t_WAY_VEC update1_cur_lru_qq;

    // Compute the lookup response
    always_comb
    begin
        lookupVecRsp = t_WAY_VEC'(0);
        lookupRsp = 'x;

        for (int w = 0; w < N_WAYS; w = w + 1)
        begin
            if (rdata1[w] == 0)
            begin
                // One hot vector response
                lookupVecRsp[w] = 1;
                // Index response
                lookupRsp = w;
                break;
            end
        end
    end

    // Lookup request has priority of writes
    assign wen1 = update1_en_qq && ! lookupEn &&
                  // Don't request writes to the same line in both ports
                  (! wen0 || (addr0 != addr1));

    //
    // Address and write data assignment.
    //
    always_comb
    begin
        // Default -- read for update if requested
        addr1 = refIdx1;
        wdata1 = 'x;

        update1_en  = refEn1 && initialized;
        update1_idx = refIdx1;
        update1_ref = refWayVec1;

        if (lookupEn)
        begin
            // Lookup
            addr1 = lookupIdx;
            wdata1 = 'x;

            // No new update can start since can't read for update
            update1_en = 1'b0;
        end
        else if (update1_en_qq)
        begin
            // Ready to write for update
            addr1 = update1_idx_qq;
            wdata1 = updatePseudoLRU(update1_cur_lru_qq, update1_ref_qq);

            // No new update can start since can't read for update
            update1_en = 1'b0;
        end
    end

    //
    // Shift update state as updates progress (read, modify, write)
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            update1_en_q <= 0;
            update1_en_qq <= 0;
        end
        else
        begin
            // Register read for update requests made this cycle
            update1_en_q <= update1_en;
            update1_idx_q <= update1_idx;
            update1_ref_q <= update1_ref;

            // Consume read response for update.  Moving the pipeline
            // conditionally allows updates to sit in the qq slot until
            // a write cycle becomes available.
            if (update1_en_q)
            begin
                update1_en_qq <= update1_en_q;
                update1_idx_qq <= update1_idx_q;
                update1_ref_qq <= update1_ref_q;
                update1_cur_lru_qq <= rdata1;
            end
            else if (! lookupEn)
            begin
                // If a write for update was pending it completed this cycle
                update1_en_qq <= 1'b0;
            end
        end 
    end

endmodule // cci_mpf_prim_lru_pseudo
