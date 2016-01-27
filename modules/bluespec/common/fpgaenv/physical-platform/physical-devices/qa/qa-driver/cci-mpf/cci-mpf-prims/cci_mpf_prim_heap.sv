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

//
// Single ported implementation. Multi-ported implementation is below.
//
module cci_mpf_prim_heap
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic enq,                                // Allocate an entry
    input  logic [N_DATA_BITS-1 : 0] enqData,
    output logic notFull,                            // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx, // Index of new entry

    input  logic [$clog2(N_ENTRIES)-1 : 0] readReq,  // Read requested index
    output logic [N_DATA_BITS-1 : 0] readRsp,        // Read data (cycle after req)

    input  logic free,                               // enable free freeIdx
    input  logic [$clog2(N_ENTRIES)-1 : 0] freeIdx
    );

    logic [$clog2(N_ENTRIES)-1 : 0] readReq0[0 : 0];
    logic [N_DATA_BITS-1 : 0] readRsp0[0 : 0];
    assign readReq0[0] = readReq;
    assign readRsp = readRsp0[0];

    logic free0[0 : 0];
    logic [$clog2(N_ENTRIES)-1 : 0] freeIdx0[0 : 0];
    assign free0[0] = free;
    assign freeIdx0[0] = freeIdx;

    cci_mpf_prim_heap_multi
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_READ_PORTS(1),
        .MIN_FREE_SLOTS(MIN_FREE_SLOTS)
        )
      h(
        .clk,
        .reset_n,
        .enq,
        .enqData,
        .notFull,
        .allocIdx,
        .readReq(readReq0),
        .readRsp(readRsp0),
        .free(free0),
        .freeIdx(freeIdx0)
        );

endmodule


//
// Multi ported implementation. There is only one enq/alloc port but
// multiple read and free ports.
//
module cci_mpf_prim_heap_multi
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_READ_PORTS = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    input  logic enq,                                // Allocate an entry
    input  logic [N_DATA_BITS-1 : 0] enqData,
    output logic notFull,                            // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx, // Index of new entry

    // Read requested index
    input  logic [$clog2(N_ENTRIES)-1 : 0] readReq[0 : N_READ_PORTS-1],
    // Read data (cycle after req)
    output logic [N_DATA_BITS-1 : 0] readRsp[0 : N_READ_PORTS-1],

    // enable free freeIdx
    input  logic free[0 : N_READ_PORTS-1],
    input  logic [$clog2(N_ENTRIES)-1 : 0] freeIdx[0 : N_READ_PORTS-1]
    );

    typedef logic [N_DATA_BITS-1 : 0] t_DATA;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;

    // Track whether an entry is free or busy
    logic [N_ENTRIES-1 : 0] notBusy;

    t_IDX nextAlloc;
    assign allocIdx = nextAlloc;


    // ====================================================================
    //
    // Slots are allocated round robin instead of using a complicated free
    // list. There must be at least MIN_FREE_SLOTS in the oldest positions.
    //
    // For timing we compute notFull in advance.  To guarantee
    // MIN_FREE_SLOTS next cycle we add one to the requirement, naming
    // the stronger requirement MIN_FREE_SLOTS_Q.
    // ====================================================================

    localparam MIN_FREE_SLOTS_Q = MIN_FREE_SLOTS + 1;

    // notBusyRepl replicates the low bits of notBusy at the end to avoid
    // computing wrap-around.
    logic [MIN_FREE_SLOTS_Q + N_ENTRIES-1 : 0] notBusyRepl;
    assign notBusyRepl = {notBusy[MIN_FREE_SLOTS_Q-1 : 0], notBusy};

    // The next MIN_FREE_SLOTS_Q entries must be free
    always_ff @(posedge clk)
    begin
        notFull <= &(notBusyRepl[nextAlloc +: MIN_FREE_SLOTS_Q]);
    end

    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            nextAlloc <= 0;
        end
        else if (enq)
        begin
            nextAlloc <= (nextAlloc == t_IDX'(N_ENTRIES-1)) ?
                             t_IDX'(0) : nextAlloc + 1;

            assert (notBusy[nextAlloc]) else
                $fatal("cci_mpf_prim_heap: Can't ENQ when FULL!");
        end
    end


    // ====================================================================
    //
    // Heap memory. Replicate the memory for each read port in order to
    // support simultaneous enq and read on all ports.
    //
    // ====================================================================

    t_DATA mem[0 : N_READ_PORTS-1][0 : N_ENTRIES-1];

    genvar p;
    generate
        for (p = 0; p < N_READ_PORTS; p = p + 1)
        begin : memory
            always_ff @(posedge clk)
            begin
                // Value available one cycle after request.
                readRsp[p] <= mem[p][readReq[p]];

                if (enq)
                begin
                    mem[p][allocIdx] <= enqData;
                end
            end
        end
    endgenerate


    //
    // Free list.
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            notBusy <= ~ (N_ENTRIES'(0));
        end
        else
        begin
            if (enq)
            begin
                notBusy[allocIdx] <= 1'b0;
            end

            for (int i = 0; i < N_READ_PORTS; i = i + 1)
            begin
                if (free[i])
                begin
                    notBusy[freeIdx[i]] <= 1'b1;
                end
            end
        end
    end

endmodule // cci_mpf_prim_heap
