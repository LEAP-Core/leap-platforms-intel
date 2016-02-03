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

//
// Output buffered scoreboard that registers the data coming from the
// scoreboard BRAM and sends it to a FIFO in order to maintain full
// throughput while avoiding a combinational control loop.
//

module cci_mpf_prim_scoreboard_obuf
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset,

    // Add a new entry to the scoreboard.  No payload, just control.
    // The scoreboard returns a handle -- the index where the payload should
    // be written.
    input  logic enq_en,                            // Allocate an entry
    input  logic [N_META_BITS-1 : 0] enqMeta,       // Save meta-data for new entry
    output logic notFull,                           // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] enqIdx,  // Index of new entry

    // Payload write.  No ready signal.  The scoreboard must always be ready
    // to receive data.
    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,
    input  logic [N_DATA_BITS-1 : 0] enqData,

    // Ordered output
    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    output logic [N_DATA_BITS-1 : 0] first,         // Data for oldest entry
    output logic [N_META_BITS-1 : 0] firstMeta      // Meta-data for oldest entry
    );

    typedef logic [N_DATA_BITS-1 : 0] t_data;
    typedef logic [N_META_BITS-1 : 0] t_meta_data;

    logic sc_deq_en;
    logic sc_not_empty;
    t_data sc_first;
    t_meta_data sc_first_meta;

    //
    // Instantiate the scoreboard.
    //
    cci_mpf_prim_scoreboard
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_META_BITS(N_META_BITS),
        .MIN_FREE_SLOTS(MIN_FREE_SLOTS)
        )
      sb
       (
        .clk,
        .reset,
        .enq_en,
        .enqMeta,
        .notFull,
        .enqIdx,
        .enqData_en,
        .enqDataIdx,
        .enqData,
        .deq_en(sc_deq_en),
        .notEmpty(sc_not_empty),
        .first(sc_first),
        .firstMeta(sc_first_meta)
        );

    //
    // Register stage.
    //
    logic sc_deq_en_q;
    t_data sc_first_q;
    t_meta_data sc_first_meta_q;

    always_ff @(posedge clk)
    begin
        sc_deq_en_q <= sc_deq_en;
        sc_first_q <= sc_first;
        sc_first_meta_q <= sc_first_meta;
    end

    //
    // Output FIFO stage.
    //
    logic fifo_full;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(N_DATA_BITS + N_META_BITS),
        .N_ENTRIES(4),
        .THRESHOLD(2)
        )
      fifo
       (
        .clk,
        .reset,
        .enq_data({ sc_first_meta_q, sc_first_q }),
        .enq_en(sc_deq_en_q),
        .notFull(),
        .almostFull(fifo_full),
        .first({ firstMeta, first }),
        .deq_en,
        .notEmpty
        );

    // Transfer from scoreboard to FIFO when data is ready and the FIFO
    // has space for new data plus whatever may be in flight already.
    assign sc_deq_en = sc_not_empty && ! fifo_full;

endmodule // cci_mpf_prim_scoreboard_obuf
