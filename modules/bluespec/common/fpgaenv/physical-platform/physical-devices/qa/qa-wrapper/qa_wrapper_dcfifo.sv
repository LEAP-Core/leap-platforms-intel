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

module qa_wrapper_dcfifo
  #(
    parameter DEPTH = 1,
    parameter WIDTH = 1
    )
   (
    input  logic sClk,
    input  logic sRst,
    input  logic dClk,

    input  logic [WIDTH-1 : 0] enq_data,
    input  logic enq_en,
    output logic notFull,

    output logic [WIDTH-1 : 0] first,
    input  logic deq,
    output logic notEmpty
    );

    logic wr_full;
    assign notFull = ~ wr_full;

    logic fifo_rd_req;
    logic fifo_rd_empty;

    // Read from DCFIFO if it has data and first is ready to accept new data
    assign fifo_rd_req = ! fifo_rd_empty && (deq || ! notEmpty);

    always_ff @(posedge dClk)
    begin
        notEmpty <= (notEmpty && ! deq) || ! fifo_rd_empty;

        if (sRst)
        begin
            notEmpty <= 1'b0;
        end
    end

    localparam DEPTH_RADIX = (DEPTH > 1) ? $clog2(DEPTH) : 1;

    ccip_afifo_channel
      #(
        .DATA_WIDTH(WIDTH),
        .DEPTH_RADIX(DEPTH_RADIX)
        )
      dcf
       (
        .wrclk(sClk),
        .aclr(sRst),
        .rdclk(dClk),

        .data(enq_data),
        .wrreq(enq_en),
        .wrfull(wr_full),

        .q(first),
        .rdreq(fifo_rd_req),
        .rdempty(fifo_rd_empty),

        .rdusedw(),
        .wrusedw(),
        .rdfull(),
        .wrempty()
      );

endmodule // qa_wrapper_dcfifo
