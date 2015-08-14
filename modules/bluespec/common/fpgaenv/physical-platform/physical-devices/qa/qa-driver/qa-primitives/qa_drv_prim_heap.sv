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

module qa_drv_prim_heap
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64
    )
   (
    input  logic clk,
    input  logic resetb,

    input  logic enq,                                // Allocate an entry
    input  logic [N_DATA_BITS-1 : 0] enqData,
    output logic notFull,                            // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] allocIdx, // Index of new entry

    input  logic [$clog2(N_ENTRIES)-1 : 0] readReq,  // Read requested index
    output logic [N_DATA_BITS-1 : 0] readRsp,        // Read data (cycle after req)

    input  logic free,                               // enable free freeIdx
    input  logic [$clog2(N_ENTRIES)-1 : 0] freeIdx
    );

    typedef logic [N_DATA_BITS-1 : 0] t_DATA;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;

    // Track whether an entry is free or busy
    reg [N_ENTRIES-1 : 0] notBusy;

    t_IDX nextAlloc;

    assign notFull = notBusy[nextAlloc];
    assign allocIdx = nextAlloc;

    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            nextAlloc <= 0;
        end
        else if (enq)
        begin
            nextAlloc <= (nextAlloc == t_IDX'(N_ENTRIES-1)) ?
                             t_IDX'(0) : nextAlloc + 1;

            assert (notFull) else
                $fatal("qa_drv_prim_heap: Can't ENQ when FULL!");
        end
    end


    //
    // Heap memory.
    //
    t_DATA mem[0 : N_ENTRIES-1];

    always_ff @(posedge clk)
    begin
        // Value available one cycle after request.
        readRsp <= mem[readReq];

        if (enq)
        begin
            mem[allocIdx] <= enqData;
        end
    end


    //
    // Free list.
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            notBusy <= ~ (N_ENTRIES'(0));
        end
        else
        begin
            if (enq)
            begin
                notBusy[allocIdx] <= 1'b0;
            end

            if (free)
            begin
                notBusy[freeIdx] <= 1'b1;
            end
        end
    end

endmodule // qa_drv_prim_heap
