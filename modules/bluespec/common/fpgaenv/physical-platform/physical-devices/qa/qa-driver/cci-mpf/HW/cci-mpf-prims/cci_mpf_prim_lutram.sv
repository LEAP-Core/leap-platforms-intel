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
// LUT RAM
//

module cci_mpf_prim_lutram
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic wen,
    input  logic [N_DATA_BITS-1 : 0] wdata
    );

    // Quartus uses Block RAM when N_DATA_BITS is 1 even when MLAB is
    // specified, perhaps because the MUX required for 1 bit access is slow.
    // The resulting timing is quite different.  In the spirit of giving
    // coders what they asked for, code here forces 1 bit memory to LUTRAM.
    // Changing N_DATA_BITS to 2 and passing in a dummy bit causes Quartus
    // to generate LUTRAM and doesn't waste space because the extra bit is
    // dropped in synthesis.
    localparam REQ_DATA_WIDTH = (N_DATA_BITS == 1) ? 2 : N_DATA_BITS;

    logic [REQ_DATA_WIDTH-1 : 0] data[0 : N_ENTRIES-1] /* synthesis ramstyle = "MLAB, no_rw_check" */;

    //
    // Delay writes by a cycle for for timing and add a bypass to guarantee
    // there is never a read/write of the same location in a single cycle.
    //
    logic [$clog2(N_ENTRIES)-1 : 0] waddr_q;
    logic wen_q;
    logic [N_DATA_BITS-1 : 0] wdata_q;

    // Bypass read response when writing the same location
    assign rdata = (! wen_q || (raddr != waddr_q)) ?
                       N_DATA_BITS'(data[raddr]) :
                       wdata_q;

    always_ff @(posedge clk)
    begin
        waddr_q <= waddr;
        wen_q <= wen;
        wdata_q <= wdata;

        if (wen_q)
        begin
            data[waddr_q] <= REQ_DATA_WIDTH'(wdata_q);
        end
    end

endmodule // cci_mpf_prim_lutram



//
// LUT RAM initialized with a constant on reset.
//
module cci_mpf_prim_lutram_init
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,

    parameter INIT_VALUE = N_DATA_BITS'(0)
    )
   (
    input  logic clk,
    input  logic reset,
    // Goes high after initialization complete and stays high.
    output logic rdy,


    input  logic [$clog2(N_ENTRIES)-1 : 0] raddr,
    output logic [N_DATA_BITS-1 : 0] rdata,

    input  logic [$clog2(N_ENTRIES)-1 : 0] waddr,
    input  logic wen,
    input  logic [N_DATA_BITS-1 : 0] wdata
    );

    logic [$clog2(N_ENTRIES)-1 : 0] waddr_local;
    logic wen_local;
    logic [N_DATA_BITS-1 : 0] wdata_local;

    cci_mpf_prim_lutram
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS)
        )
      ram
       (
        .clk,
        .reset,

        .raddr,
        .rdata,

        .waddr(waddr_local),
        .wen(wen_local),
        .wdata(wdata_local)
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
            rdy <= &(waddr_init);
        end
    end

endmodule // cci_mpf_prim_lutram_init
