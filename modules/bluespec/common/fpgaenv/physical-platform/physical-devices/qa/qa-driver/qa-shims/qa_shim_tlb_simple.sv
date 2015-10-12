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

`include "qa_driver.vh"


//
// Map virtual to physical addresses.  The AFU and QLP interfaces are thus
// difference widths.
//

module qa_shim_tlb_simple
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_QLP_RX_HDR_WIDTH = 18,
    parameter CCI_QLP_TX_HDR_WIDTH = 61,
    parameter CCI_AFU_RX_HDR_WIDTH = 24,
    parameter CCI_AFU_TX_HDR_WIDTH = 99,
    parameter CCI_TAG_WIDTH = 13
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    qlp_interface.to_qlp qlp,

    // Connections toward user code.
    qlp_interface.to_afu afu
    );

    logic resetb;
    assign resetb = qlp.resetb;

    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_AFU_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_AFU_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqC0Tx;
    logic deqC1Tx;

    qa_shim_buffer_afu
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_AFU_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_AFU_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      buffer
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqC0Tx,
         .deqC1Tx
         );

    assign afu_buf.resetb = qlp.resetb;

    //
    // Almost full signals in the buffered input are ignored --
    // replaced by deq signals and the buffer state.  Set them
    // to 1 to be sure they are ignored.
    //
    assign afu_buf.C0TxAlmFull = 1'b1;
    assign afu_buf.C1TxAlmFull = 1'b1;


    // ====================================================================
    //
    //  Requests
    //
    // ====================================================================

    assign deqC0Tx = afu_buf.C0TxRdValid && ! qlp.C0TxAlmFull;

    assign qlp.C0TxHdr = $bits(qlp.C0TxHdr)'(afu_buf.C0TxHdr);
    assign qlp.C0TxRdValid = deqC0Tx;


    assign deqC1Tx = (afu_buf.C1TxWrValid || afu_buf.C1TxIrValid) &&
                     ! qlp.C1TxAlmFull;

    assign qlp.C1TxHdr = $bits(qlp.C1TxHdr)'(afu_buf.C1TxHdr);
    assign qlp.C1TxData = afu_buf.C1TxData;
    assign qlp.C1TxWrValid = afu_buf.C1TxWrValid && deqC1Tx;
    assign qlp.C1TxIrValid = afu_buf.C1TxIrValid && deqC1Tx;


    // ====================================================================
    //
    //  Responses
    //
    // ====================================================================

    assign afu_buf.C0RxHdr = $bits(afu_buf.C0RxHdr)'(qlp.C0RxHdr);
    assign afu_buf.C0RxData = qlp.C0RxData;
    assign afu_buf.C0RxWrValid = qlp.C0RxWrValid;
    assign afu_buf.C0RxRdValid = qlp.C0RxRdValid;
    assign afu_buf.C0RxCgValid = qlp.C0RxCgValid;
    assign afu_buf.C0RxUgValid = qlp.C0RxUgValid;
    assign afu_buf.C0RxIrValid = qlp.C0RxIrValid;

    assign afu_buf.C1RxHdr = $bits(afu_buf.C1RxHdr)'(qlp.C1RxHdr);
    assign afu_buf.C1RxWrValid = qlp.C1RxWrValid;
    assign afu_buf.C1RxIrValid = qlp.C1RxIrValid;

endmodule // qa_shim_tlb_simple
