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
// Scoreboard that behaves like a FIFO that allows out of order arrival of
// the payload.
//

module qa_drv_scoreboard
  #(parameter N_ENTRIES = 32,
              N_DATA_BITS = 64)
    (input  logic clk,
     input  logic resetb,

     // Add a new entry to the scoreboard.  No payload, just control.
     // The scoreboard returns a handle -- the index where the payload should
     // be written.
     input  logic enq_en,
     output logic notFull,
     output [$clog2(N_ENTRIES)-1 : 0] enqIdx,

     // Payload write.  No ready signal.  The scoreboard must always be ready
     // to receive data.
     input  logic enqData_en,
     input  [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,
     input  [N_DATA_BITS-1 : 0] enqData,

     // Ordered output
     input  logic deq_en,
     output logic notEmpty,
     output logic [N_DATA_BITS-1 : 0] first
     );

    typedef logic [N_DATA_BITS-1 : 0] t_DATA;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;

    // Scoreboard is empty when oldest == newest and full when
    // newest + 1 == oldest.
    t_IDX newest;
    t_IDX oldest;
    t_IDX oldest_next;

    // Track data arrival
    reg [N_ENTRIES-1 : 0] dataValid;
    logic [N_ENTRIES-1 : 0] dataValid_next;

    assign notFull = (newest + 1 != oldest);

    // Data storage
    t_DATA data[0 : N_ENTRIES-1];


    // enq allocates a slot and returns the index of the slot.
    assign enqIdx = newest;

    always_ff @(posedge clk)
    begin
        if (! resetb)
            newest <= 0;
        else if (enq_en)
            newest <= newest + 1;
    end


    // notEmpty is true after data arrives.  Client consumes the entry by
    // asserting deq.
    assign oldest_next = oldest + deq_en;

    always_ff @(posedge clk)
    begin
        if (! resetb)
            oldest <= 0;
        else
            oldest <= oldest_next;
    end


    // Manage the data storage as a memory
    always_ff @(posedge clk)
    begin
        first <= data[oldest_next];

        if (enqData_en)
        begin
            data[enqDataIdx] <= enqData;
        end
    end


    // Track valid data
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            dataValid <= 0;
        end
        else
        begin
            dataValid <= dataValid_next;
        end
    end

    always_comb
    begin
        dataValid_next = dataValid;

        // Clear on deq
        if (deq_en)
        begin
            dataValid_next[oldest] = 0;
        end

        // Set when data arrives
        if (enqData_en)
        begin
            dataValid_next[enqDataIdx] = 1;
        end
    end


    // Track whether the oldest entry's data is valid.  We read from a register
    // to correspond with the lack of bypass on the memory.  notEmpty
    // will thus go high in the first cycle a data read would return the
    // correct value.
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            notEmpty <= 0;
        end
        else
        begin
            notEmpty <= dataValid[oldest_next];
        end
    end


    always_comb
    begin
        if (enq_en && ! notFull)
        begin
            $display("qa_drv_scoreboard: ENQ when FULL!");
            $finish;           
        end

        if (deq_en && ! notEmpty)
        begin
            $display("qa_drv_scoreboard: DEQ when EMPTY!");
            $finish;           
        end
    end

endmodule // qa_dvr_scoreboard
