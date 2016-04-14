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

//
// Simple dual port Block RAM.
//

module cci_mpf_prim_simple_ram
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0
    )
   (
    input  logic clk,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    logic [N_DATA_BITS-1 : 0] mem_rd[0 : N_OUTPUT_REG_STAGES];
    assign rdata = mem_rd[N_OUTPUT_REG_STAGES];

    // If the output data is registered then request a register stage in
    // the megafunction, giving it an opportunity to optimize the location.
    //
    localparam OUTDATA_REGISTERED = (N_OUTPUT_REG_STAGES == 0) ? "UNREGISTERED" :
                                                                 "CLOCK0";
    localparam OUTDATA_IDX = (N_OUTPUT_REG_STAGES == 0) ? 0 : 1;


    altsyncram
      #(
        .operation_mode("DUAL_PORT"),
        .width_a(N_DATA_BITS),
        .widthad_a($clog2(N_ENTRIES)),
        .numwords_a(N_ENTRIES),
        .width_b(N_DATA_BITS),
        .widthad_b($clog2(N_ENTRIES)),
        .numwords_b(N_ENTRIES),
        .rdcontrol_reg_b("CLOCK0"),
        .address_reg_b("CLOCK0"),
        .outdata_reg_b(OUTDATA_REGISTERED),
        .read_during_write_mode_mixed_ports("OLD_DATA")
        )
      data
       (
        .clock0(clk),

        .wren_a(wen),
        .address_a(waddr),
        .data_a(wdata),

        .address_b(raddr),
        .q_b(mem_rd[OUTDATA_IDX]),

        // Legally unconnected ports -- get rid of lint errors
        .wren_b(),
        .rden_a(),
        .rden_b(),
        .data_b(),
        .clock1(),
        .clocken0(),
        .clocken1(),
        .clocken2(),
        .clocken3(),
        .aclr0(),
        .aclr1(),
        .byteena_a(),
        .byteena_b(),
        .addressstall_a(),
        .addressstall_b(),
        .q_a(),
        .eccstatus()
        );


    genvar s;
    generate
        for (s = 1; s < N_OUTPUT_REG_STAGES; s = s + 1)
        begin: r
            always_ff @(posedge clk)
            begin
                mem_rd[s+1] <= mem_rd[s];
            end
        end
    endgenerate

endmodule // cci_mpf_prim_simple_ram



//
// Simple dual port RAM initialized with a constant on reset.
//
module cci_mpf_prim_simple_ram_init
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0,

    parameter INIT_VALUE = N_DATA_BITS'(0)
    )
   (
    input  logic clk,
    input  logic reset,
    // Goes high after initialization complete and stays high.
    output logic rdy,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    logic [$clog2(N_ENTRIES)-1 : 0] waddr_local;
    logic wen_local;
    logic [N_DATA_BITS-1 : 0] wdata_local;

    cci_mpf_prim_simple_ram
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES)
        )
      ram
       (
        .clk,
        .waddr(waddr_local),
        .wen(wen_local),
        .wdata(wdata_local),
        .raddr,
        .rdata
        );

    //
    // Initialization loop
    //

    logic [$clog2(N_ENTRIES)-1 : 0] waddr_init;

    assign waddr_local = rdy ? waddr : waddr_init;
    assign wen_local = rdy ? wen : 1'b1;
    assign wdata_local = rdy ? wdata : INIT_VALUE;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rdy <= 1'b0;
            waddr_init <= 0;
        end
        else if (! rdy)
        begin
            waddr_init <= waddr_init + 1;
            rdy <= (waddr_init == (N_ENTRIES-1));
        end
    end

endmodule // cci_mpf_prim_simple_ram_init

