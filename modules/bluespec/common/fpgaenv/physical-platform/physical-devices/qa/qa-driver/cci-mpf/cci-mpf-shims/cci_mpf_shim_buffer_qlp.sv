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

`include "cci_mpf_if.vh"


//
// This is more a primitive shim than a full fledged shim.  It takes a
// QLP-side raw connection (wires) and adds one cycle of buffering to
// all the RX signals that flow toward the AFU.  The TX signals flowing
// toward the QLP pass through as wires.
//
// This structure is useful when a shim needs to look up some data
// associated with a response that is stored in block RAM.  The RAM read
// request can be triggered when the response arrives from the QLP and
// the RAM response is then available when the response exits the
// buffer built here.
//
// Unlike the equivalent AFU buffer there is no flow control.  The CCI
// interface does not provide for back pressure on the flow of responses.
//

module cci_mpf_shim_buffer_qlp
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,
    // Register outbound signals if nonzero.
    parameter REGISTER_OUTBOUND = 0
    )
   (
    input  logic clk,

    // Raw unbuffered connection.  This is the QLP-side connection of the
    // parent module.
    cci_mpf_if.to_qlp qlp_raw,

    // Generated buffered connection.  The confusing interface direction
    // arises because the shim is an interposer on the QLP side of a
    // standard shim.
    cci_mpf_if.to_afu qlp_buf
    );

    assign qlp_buf.resetb = qlp_raw.resetb;

    //
    // Tx wires pass through toward the QLP. They are straight assignments
    // if REGISTER_OUTBOUND is 0.
    //
    generate
        if (REGISTER_OUTBOUND == 0)
        begin
            always_comb
            begin
                qlp_raw.C0TxHdr = qlp_buf.C0TxHdr;
                qlp_raw.C0TxRdValid = qlp_buf.C0TxRdValid;
                qlp_buf.C0TxAlmFull = qlp_raw.C0TxAlmFull;

                qlp_raw.C1TxHdr = qlp_buf.C1TxHdr;
                qlp_raw.C1TxData = qlp_buf.C1TxData;
                qlp_raw.C1TxWrValid = qlp_buf.C1TxWrValid;
                qlp_raw.C1TxIrValid = qlp_buf.C1TxIrValid;
                qlp_buf.C1TxAlmFull = qlp_raw.C1TxAlmFull;
            end
        end
        else
        begin
            always_ff @(posedge clk)
            begin
                qlp_raw.C0TxHdr <= qlp_buf.C0TxHdr;
                qlp_raw.C0TxRdValid <= qlp_buf.C0TxRdValid;
                qlp_buf.C0TxAlmFull <= qlp_raw.C0TxAlmFull;

                qlp_raw.C1TxHdr <= qlp_buf.C1TxHdr;
                qlp_raw.C1TxData <= qlp_buf.C1TxData;
                qlp_raw.C1TxWrValid <= qlp_buf.C1TxWrValid;
                qlp_raw.C1TxIrValid <= qlp_buf.C1TxIrValid;
                qlp_buf.C1TxAlmFull <= qlp_raw.C1TxAlmFull;
            end
        end
    endgenerate

    //
    // Rx input is registered for a one cycle delay.
    //
    always_ff @(posedge clk)
    begin
        qlp_buf.C0RxHdr <= qlp_raw.C0RxHdr;
        qlp_buf.C0RxData <= qlp_raw.C0RxData;
        qlp_buf.C0RxWrValid <= qlp_raw.C0RxWrValid;
        qlp_buf.C0RxRdValid <= qlp_raw.C0RxRdValid;
        qlp_buf.C0RxCgValid <= qlp_raw.C0RxCgValid;
        qlp_buf.C0RxUgValid <= qlp_raw.C0RxUgValid;
        qlp_buf.C0RxIrValid <= qlp_raw.C0RxIrValid;

        qlp_buf.C1RxHdr <= qlp_raw.C1RxHdr;
        qlp_buf.C1RxWrValid <= qlp_raw.C1RxWrValid;
        qlp_buf.C1RxIrValid <= qlp_raw.C1RxIrValid;
    end

endmodule // cci_mpf_shim_buffer_qlp

