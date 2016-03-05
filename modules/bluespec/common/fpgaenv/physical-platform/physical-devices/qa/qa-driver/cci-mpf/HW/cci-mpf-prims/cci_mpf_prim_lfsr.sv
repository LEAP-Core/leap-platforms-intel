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

module cci_mpf_prim_lfsr12
  #(
    parameter INITIAL_VALUE = 12'b101001101011
    )
   (
    input  logic clk,
    input  logic reset,
    input  logic en,
    output logic [11:0] value
    );

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            value <= INITIAL_VALUE;
        end
        else if (en)
        begin
            value[11] <= value[0];
            value[10] <= value[11];
            value[9]  <= value[10];
            value[8]  <= value[9];
            value[7]  <= value[8];
            value[6]  <= value[7];
            value[5]  <= value[6] ^ value[0];
            value[4]  <= value[5];
            value[3]  <= value[4] ^ value[0];
            value[2]  <= value[3];
            value[1]  <= value[2];
            value[0]  <= value[1] ^ value[0];
        end
    end

endmodule // cci_mpf_prim_lfsr12
