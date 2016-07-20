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

module cci_mpf_prim_ram_simple
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,

    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0,

    // Register writes for a cycle and optionally bypass delayed writes
    // to reads in the delay cycle?  In some cases it is better to impose
    // a delay on the read path for the bypass when the write path has
    // tighter timing.
    parameter REGISTER_WRITES = 0,
    parameter BYPASS_REGISTERED_WRITES = 1
    )
   (
    input  logic clk,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    logic [N_DATA_BITS-1 : 0] c_rdata;

    cci_mpf_prim_ram_simple_base
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .REGISTER_READS(N_OUTPUT_REG_STAGES),
        .REGISTER_WRITES(REGISTER_WRITES),
        .BYPASS_REGISTERED_WRITES(BYPASS_REGISTERED_WRITES)
        )
      ram
       (
        .clk,
        .waddr,
        .wen,
        .wdata,
        .raddr,
        .rdata(c_rdata)
        );

    //
    // Optional extra registered read responses
    //
    genvar s;
    generate
        if (N_OUTPUT_REG_STAGES <= 1)
        begin : nr
            // 0 or 1 stages handled in base primitive
            assign rdata = c_rdata;
        end
        else
        begin : r
            logic [N_DATA_BITS-1 : 0] mem_rd[2 : N_OUTPUT_REG_STAGES];
            assign rdata = c_rdata[N_OUTPUT_REG_STAGES];

            always_ff @(posedge clk)
            begin
                mem_rd[2] <= c_rdata;
            end

            for (s = 2; s < N_OUTPUT_REG_STAGES; s = s + 1)
            begin : shft
                always_ff @(posedge clk)
                begin
                    mem_rd[s+1] <= mem_rd[s];
                end
            end
        end
    endgenerate
endmodule // cci_mpf_prim_ram_simple


//
// Simple dual port RAM initialized with a constant on reset.
//
module cci_mpf_prim_ram_simple_init
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    // Number of extra stages of output register buffering to add
    parameter N_OUTPUT_REG_STAGES = 0,
    parameter REGISTER_WRITES = 0,
    parameter BYPASS_REGISTERED_WRITES = 1,

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

    cci_mpf_prim_ram_simple
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(N_OUTPUT_REG_STAGES),
        .REGISTER_WRITES(REGISTER_WRITES),
        .BYPASS_REGISTERED_WRITES(BYPASS_REGISTERED_WRITES)
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

endmodule // cci_mpf_prim_ram_simple_init



//
// Base implementation configured by the primary modules above.
//
module cci_mpf_prim_ram_simple_base
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,

    // Register reads if non-zero
    parameter REGISTER_READS = 0,

    // Register writes for a cycle and optionally bypass delayed writes
    // to reads in the delay cycle?  In some cases it is better to impose
    // a delay on the read path for the bypass when the write path has
    // tighter timing.
    parameter REGISTER_WRITES = 0,
    parameter BYPASS_REGISTERED_WRITES = 1
    )
   (
    input  logic clk,

    input  logic wen,
    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic [N_DATA_BITS-1 : 0] wdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata
    );

    // If the output data is registered then request a register stage in
    // the megafunction, giving it an opportunity to optimize the location.
    //
    localparam OUTDATA_REGISTERED = (REGISTER_READS == 0) ? "UNREGISTERED" :
                                                            "CLOCK0";

    localparam OUTDATA_IDX = (REGISTER_READS == 0) ? 0 : 1;

    logic c_wen;
    logic [$clog2(N_ENTRIES)-1 : 0] c_waddr;
    logic [N_DATA_BITS-1 : 0] c_wdata;
    logic [N_DATA_BITS-1 : 0] c_rdata;

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

        .wren_a(c_wen),
        .address_a(c_waddr),
        .data_a(c_wdata),

        .address_b(raddr),
        .q_b(c_rdata),

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


    //
    // Bypass logic when writes are registered.
    //
    generate
        if (REGISTER_WRITES == 0)
        begin : nwr
            // No write buffering or bypass
            assign c_wen = wen;
            assign c_waddr = waddr;
            assign c_wdata = wdata;

            assign rdata = c_rdata;
        end
        else if (BYPASS_REGISTERED_WRITES == 0)
        begin : wr
            // Register writes with no bypass
            always_ff @(posedge clk)
            begin
                c_wen <= wen;
                c_waddr <= waddr;
                c_wdata <= wdata;
            end

            assign rdata = c_rdata;
        end
        else
        begin : wrb
            // Register writes and bypass write data to reads in the delay slot
            logic addr_matched[0 : 1];
            logic [N_DATA_BITS-1 : 0] c_wdata_history[0 : 1];

            initial c_wen = 1'b0;
            initial addr_matched[0] = 1'b0;
            initial addr_matched[1] = 1'b0;

            // Delay write one cycle
            always @(posedge clk)
            begin
                c_wen <= wen;
                c_waddr <= waddr;
                c_wdata <= wdata;

                // Bypass logic
                addr_matched[0] <= (c_wen && (c_waddr == raddr));
                addr_matched[1] <= addr_matched[0];
                c_wdata_history[0] <= c_wdata;
                c_wdata_history[1] <= c_wdata_history[0];
            end

            // Bypass delayed write to read.  The number of cycles to delay
            // the bypass depends on the altsyncram buffering.
            assign rdata =
                (! addr_matched[OUTDATA_IDX]) ? c_rdata :
                                                c_wdata_history[OUTDATA_IDX];
        end
    endgenerate

endmodule // cci_mpf_prim_ram_simple_base