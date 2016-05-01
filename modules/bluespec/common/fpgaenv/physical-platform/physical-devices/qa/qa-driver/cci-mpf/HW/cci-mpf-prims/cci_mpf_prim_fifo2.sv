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
// FIFO --
//   A FIFO with two storage elements supporting full pipelining.
//

module cci_mpf_prim_fifo2
  #(
    parameter N_DATA_BITS = 32,

    // Register output if non-zero
    parameter REGISTER_OUTPUT = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic                     enq_en,
    output logic                     notFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic                     deq_en,
    output logic                     notEmpty
    );

    logic almostFull;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(2),
        .REGISTER_OUTPUT(REGISTER_OUTPUT)
        )
      fifo(.*);

endmodule // cci_mpf_prim_fifo2
