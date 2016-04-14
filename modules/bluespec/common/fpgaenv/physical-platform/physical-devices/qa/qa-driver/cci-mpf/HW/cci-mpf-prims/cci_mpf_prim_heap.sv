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
// A simple heap implementation.  Elements are given out round robin to
// simplify the allocator.  Values are written to the heap at allocation
// time.
//

module cci_mpf_prim_heap
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1,
    // Register enq, delaying the write by a cycle?
    parameter REGISTER_INPUT = 0,
    // Number of additional register stages on readRsp
    parameter N_OUTPUT_REG_STAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic enq,                                // Allocate an entry
    input  logic [N_DATA_BITS-1 : 0] enqData,
    output logic notFull,                            // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx, // Index of new entry

    input  logic [$clog2(N_ENTRIES)-1 : 0] readReq,  // Read requested index
    output logic [N_DATA_BITS-1 : 0] readRsp,        // Read data (cycle after req)

    input  logic free,                               // enable free freeIdx
    input  logic [$clog2(N_ENTRIES)-1 : 0] freeIdx
    );

    typedef logic [N_DATA_BITS-1 : 0] t_data;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;


    // ====================================================================
    //
    // Heap writes either happen the cycle requested (default) or are
    // registered for timing and delayed a cycle. The allocation pointers
    // and counters are updated the cycle requested independent of
    // the data timing.
    //
    // ====================================================================

    logic heap_enq;
    t_data heap_enqData;
    t_idx heap_allocIdx;

    generate
        if (REGISTER_INPUT == 0)
        begin : nr
            // Unregistered
            assign heap_enq = enq;
            assign heap_enqData = enqData;
            assign heap_allocIdx = allocIdx;
        end
        else
        begin : r
            // Registered
            always_ff @(posedge clk)
            begin
                heap_enq <= enq;
                heap_enqData <= enqData;
                heap_allocIdx <= allocIdx;
            end
        end
    endgenerate


    //
    // Heap memory
    //
    cci_mpf_prim_ram_simple
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES)
        )
      mem(
        .clk,

        .wen(heap_enq),
        .waddr(heap_allocIdx),
        .wdata(heap_enqData),

        .raddr(readReq),
        .rdata(readRsp)
        );


    // ====================================================================
    //
    // Free list.
    //
    // ====================================================================

    //
    // Prefetch the next entry to be allocated.
    //
    logic pop_free;
    logic free_idx_avail;
    logic [$clog2(N_ENTRIES)-1 : 0] next_free_idx;

    // Need a new entry in allocIdx?
    logic need_pop_free;
    // Is a free entry available?
    assign pop_free = need_pop_free && free_idx_avail;

    cci_mpf_prim_fifo2
      #(
        .N_DATA_BITS($clog2(N_ENTRIES))
        )
      alloc_fifo
       (
        .clk,
        .reset,
        .enq_data(next_free_idx),
        .enq_en(pop_free),
        .notFull(need_pop_free),
        .first(allocIdx),
        .deq_en(enq),
        .notEmpty(notFull)
        );


    // There are two free list heads to deal with the 2 cycle latency of
    // BRAM reads.  The lists are balanced, since both push and pop of
    // free entries are processed round-robin.
    t_idx free_head_idx[0:1];
    t_idx free_head_idx_reg[0:1];
    t_idx free_tail_idx[0:1];
    logic head_rr_select;
    logic tail_rr_select;

    logic initialized;
    t_idx init_idx;

    assign next_free_idx = free_head_idx[head_rr_select];

    //
    // Free list memory
    //
    logic free_wen;
    t_idx free_widx_next;
    t_idx free_rnext;

    cci_mpf_prim_ram_simple
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS($bits(t_idx)),
        .N_OUTPUT_REG_STAGES(1)
        )
      freeList(
        .clk,

        .wen(free_wen),
        .waddr(free_tail_idx[tail_rr_select]),
        .wdata(free_widx_next),

        .raddr(free_head_idx[head_rr_select]),
        .rdata(free_rnext)
        );


    // Pop from free list
    logic pop_free_q;
    logic pop_free_qq;
    logic head_rr_select_q;
    logic head_rr_select_qq;

    always_comb
    begin
        for (int i = 0; i < 2; i = i + 1)
        begin
            if (pop_free_qq && (head_rr_select_qq == 1'(i)))
            begin
                // Did a pop from this free list two cycles.  Receive the
                // updated head pointer.
                free_head_idx[i] = free_rnext;
            end
            else
            begin
                // No pop -- no change
                free_head_idx[i] = free_head_idx_reg[i];
            end
        end
    end

    // Track pop until the free list read response is received
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            pop_free_q <= 1'b0;
            pop_free_qq <= 1'b0;
            head_rr_select <= 1'b0;

            // Entries 0 and 1 begin as the head pointers
            free_head_idx_reg[0] <= t_idx'(0);
            free_head_idx_reg[1] <= t_idx'(1);
        end
        else
        begin
            pop_free_q <= pop_free;
            pop_free_qq <= pop_free_q;

            // Register combinationally computed free_head_idx
            free_head_idx_reg[0] <= free_head_idx[0];
            free_head_idx_reg[1] <= free_head_idx[1];
        end

        head_rr_select_q <= head_rr_select;
        head_rr_select_qq <= head_rr_select_q;

        if (pop_free)
        begin
            head_rr_select <= ~head_rr_select;
        end
    end


    // Push released entry on the tail of a list, delayed by a cycle for
    // timing.
    logic free_q;
    t_idx freeIdx_q;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            free_q <= 1'b0;
        end
        else
        begin
            free_q <= free;
        end

        freeIdx_q <= freeIdx;
    end
    
    assign free_wen = ! initialized || free_q;
    assign free_widx_next = (! initialized ? init_idx : freeIdx_q);


    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            free_tail_idx[0] <= t_idx'(0);
            free_tail_idx[1] <= t_idx'(1);
            tail_rr_select <= 1'b0;
        end
        else
        begin
            if (free_wen)
            begin
                // Move tail pointer to index just pushed
                free_tail_idx[tail_rr_select] <= free_widx_next;
                // Swap round-robin selector
                tail_rr_select <= ~tail_rr_select;
            end
        end
    end
    

    // Initialize the free list and track the number of free entries
    t_idx num_free;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            // Start pushing with entry 2 since entries 0 and 1 start as the
            // free list head pointers above.
            init_idx <= t_idx'(2);
            initialized <= 1'b0;

            num_free <= t_idx'(0);
            free_idx_avail <= 1'b0;
        end
        else
        begin
            if (! initialized)
            begin
                init_idx <= init_idx + t_idx'(1);

                if (init_idx == t_idx'(N_ENTRIES-1))
                begin
                    // Initialization complete
                    initialized <= 1'b1;

                    // Reserve two entries that must stay on the free list.
                    // This guarantees that neither free_head_idx ever goes
                    // NULL, which would require managing a special case.
                    num_free <= t_idx'(N_ENTRIES - 2);
                    free_idx_avail <= 1'b1;

                    assert (N_ENTRIES > 2 + MIN_FREE_SLOTS) else
                       $fatal("cci_mpf_prim_heap: Heap too small");
                end
            end
            else
            begin
                if (free_q && ! pop_free)
                begin
                    num_free <= num_free + t_idx'(1);
                    free_idx_avail <= ((num_free + t_idx'(1)) > t_idx'(MIN_FREE_SLOTS));

                    assert (num_free < N_ENTRIES - 2) else
                       $fatal("cci_mpf_prim_heap: Too many free items. Pushed one twice?");
                end
                else if (! free_q && pop_free)
                begin
                    num_free <= num_free - t_idx'(1);
                    free_idx_avail <= ((num_free - t_idx'(1)) > t_idx'(MIN_FREE_SLOTS));

                    assert (num_free != 0) else
                       $fatal("cci_mpf_prim_heap: alloc from empty heap!");
                end
            end
        end
    end

endmodule // cci_mpf_prim_heap
