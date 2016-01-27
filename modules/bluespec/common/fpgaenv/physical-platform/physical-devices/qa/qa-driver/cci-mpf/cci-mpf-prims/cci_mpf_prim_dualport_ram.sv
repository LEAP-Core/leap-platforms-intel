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

//
// Dual port Block RAM.  When write is enabled on a port the rdata response
// on the same port is the new data.  The rdata for the same address written
// by the other port is the old data.
//

module cci_mpf_prim_dualport_ram
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0
    )
   (
    input  logic clk0,
    input  logic [$clog2(N_ENTRIES)-1 : 0] addr0,
    input  logic wen0,
    input  logic [N_DATA_BITS-1 : 0] wdata0,
    output logic [N_DATA_BITS-1 : 0] rdata0,

    input  logic clk1,
    input  logic [$clog2(N_ENTRIES)-1 : 0] addr1,
    input  logic wen1,
    input  logic [N_DATA_BITS-1 : 0] wdata1,
    output logic [N_DATA_BITS-1 : 0] rdata1
    );

    logic [N_DATA_BITS-1 : 0] data[0 : N_ENTRIES-1];

    logic [N_DATA_BITS-1 : 0] mem_rd0[0 : N_OUTPUT_REG_STAGES];
    logic [N_DATA_BITS-1 : 0] mem_rd1[0 : N_OUTPUT_REG_STAGES];

    assign rdata0 = mem_rd0[N_OUTPUT_REG_STAGES];
    assign rdata1 = mem_rd1[N_OUTPUT_REG_STAGES];


    // Port A
    always @(posedge clk0)
    begin
        if (wen0)
        begin
            data[addr0] <= wdata0;
            // Altera includes this bypass in the sample dual write port memory.
            mem_rd0[0] <= wdata0;
        end
        else
        begin
            mem_rd0[0] <= data[addr0];
        end
    end

    // Port B
    always @(posedge clk1)
    begin
        if (wen1)
        begin
            data[addr1] <= wdata1;
            // Altera includes this bypass in the sample dual write port memory.
            mem_rd1[0] <= wdata1;
        end
        else
        begin
            mem_rd1[0] <= data[addr1];
        end
    end

    genvar s;
    generate
        for (s = 0; s < N_OUTPUT_REG_STAGES; s = s + 1)
        begin: r
            always_ff @(posedge clk0)
            begin
                mem_rd0[s+1] <= mem_rd0[s];
            end

            always_ff @(posedge clk1)
            begin
                mem_rd1[s+1] <= mem_rd1[s];
            end
        end
    endgenerate

endmodule // cci_mpf_prim_dualport_ram
