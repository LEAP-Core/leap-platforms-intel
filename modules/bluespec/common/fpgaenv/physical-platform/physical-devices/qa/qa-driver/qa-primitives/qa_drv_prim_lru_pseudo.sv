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

module qa_drv_prim_lru_pseudo
  #(
    parameter N_WAYS = 4,
    parameter N_ENTRIES = 1024
    )
   (
    input  logic clk,
    input  logic resetb,

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

    qa_drv_prim_dualport_ram
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
        if (! resetb)
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

    logic update0;
    t_ENTRY_IDX update_idx0;
    t_WAY_VEC update_way0;

    // Write if initializing or update started last cycle
    assign wen0 = update0 || ! initialized;

    //
    // Address and write data assignment.
    //
    always_comb
    begin
        if (! initialized)
        begin
            // Initializing
            addr0 = t_ENTRY_IDX'(init_idx);
            wdata0 = t_WAY_VEC'(0);
        end
        else if (update0)
        begin
            // Updating
            addr0 = update_idx0;
            wdata0 = updatePseudoLRU(rdata0, update_way0);
        end
        else
        begin
            // Not writing.  Set up for possible read for update.
            addr0 = refIdx0;
            wdata0 = 'x;
        end
    end

    //
    // Update lookup state to be used during update.
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            update0 <= 0;
        end
        else
        begin
            if (update0)
            begin
                // Completed LRU update this cycle
                update0 <= 0;
            end
            else
            begin
                update0 <= refEn0 && initialized;
                update_idx0 <= refIdx0;
                update_way0 <= refWayVec0;
            end
        end 
    end


    // ====================================================================
    //
    //   LRU storage port 1 handles this module's port 1 updates and
    //   LRU lookup requests.
    //
    // ====================================================================

    logic update1;
    t_ENTRY_IDX update_idx1;
    t_WAY_VEC update_way1;

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
    assign wen1 = update1 && ! lookupEn &&
                  // Don't request writes to the same line in both ports
                  (! wen0 || (addr0 != addr1));

    //
    // Address and write data assignment.
    //
    always_comb
    begin
        if (lookupEn)
        begin
            // Lookup
            addr1 = lookupIdx;
            wdata1 = 'x;
        end
        else if (update1)
        begin
            // Updating
            addr1 = update_idx1;
            wdata1 = updatePseudoLRU(rdata1, update_way1);
        end
        else
        begin
            // Not writing.  Set up for possible read for update.
            addr1 = refIdx1;
            wdata1 = 'x;
        end
    end

    //
    // Update lookup state to be used during update.
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            update1 <= 0;
        end
        else
        begin
            if (update1)
            begin
                // Completed LRU update this cycle
                update1 <= 0;
            end
            else
            begin
                // Lookup has priority
                update1 <= refEn1 && ! lookupEn && initialized;
                update_idx1 <= refIdx1;
                update_way1 <= refWayVec1;
            end
        end 
    end

endmodule // qa_drv_prim_lru_pseudo
