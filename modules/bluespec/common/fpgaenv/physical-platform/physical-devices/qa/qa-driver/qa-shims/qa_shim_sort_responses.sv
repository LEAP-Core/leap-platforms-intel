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
// Convert an unordered QLP interface port into a port with read responses
// coming in the same order as the original requests.
//


module qa_shim_sort_responses
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,

    parameter N_SCOREBOARD_ENTRIES=256
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

    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_SCOREBOARD_IDX;

    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqTx;

    qa_shim_buffer_lockstep_afu
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      buffer
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqTx
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
    //  Incoming requests.
    //
    // ====================================================================

    // Is either AFU making a request?
    logic c0_request_rdy;
    assign c0_request_rdy = afu_buf.C0TxRdValid;

    logic c1_request_rdy;
    assign c1_request_rdy = afu_buf.C1TxWrValid || afu_buf.C1TxIrValid;

    // Full signal that will come from the scoreboard used to sort responses.
    logic c0_scoreboard_notFull;

    // Is a request blocked by inability to forward it to the QLP or a
    // full scoreboard?
    logic c0_blocked;
    assign c0_blocked = c0_request_rdy &&
                        (qlp.C0TxAlmFull || ! c0_scoreboard_notFull);
    logic c1_blocked;
    assign c1_blocked = c1_request_rdy && qlp.C1TxAlmFull;

    // Process requests if one exists on either channel AND neither channel
    // is blocked.  The requirement that neither channel be blocked keeps
    // the two channels synchronized with respect to each other so that
    // read and write requests stay ordered relative to each other.  Other
    // shims, such as the read/write ordering shim depend on this.
    logic process_requests;
    assign process_requests = (c0_request_rdy || c1_request_rdy) &&
                              ! (c0_blocked || c1_blocked);


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    t_SCOREBOARD_IDX c0_scoreboard_enqIdx;

    logic c0_scoreboard_notEmpty;
    t_MDATA c0_scoreboard_mdata;

    qa_drv_prim_scoreboard
      #(
        .N_ENTRIES(N_SCOREBOARD_ENTRIES),
        .N_DATA_BITS($bits(qlp.C0RxData)),
        .N_META_BITS($bits(t_MDATA))
        )
      c0_scoreboard(.clk,
                    .resetb,

                    .enq_en(qlp.C0TxRdValid),
                    // Mdata field is in the low bits of the request header
                    .enqMeta(t_MDATA'(afu_buf.C0TxHdr)),
                    .notFull(c0_scoreboard_notFull),
                    .enqIdx(c0_scoreboard_enqIdx),

                    .enqData_en(qlp.C0RxRdValid),
                    .enqDataIdx(t_SCOREBOARD_IDX'(qlp.C0RxHdr)),
                    .enqData(qlp.C0RxData),

                    .deq_en(afu_buf.C0RxRdValid),
                    .notEmpty(c0_scoreboard_notEmpty),
                    .first(afu_buf.C0RxData),
                    .firstMeta(c0_scoreboard_mdata));

    // Forward requests toward the QLP.  Replace the Mdata entry with the
    // scoreboard index.  The original Mdata is saved in the scoreboard
    // and restored when the response is returned.
    assign qlp.C0TxHdr = { afu_buf.C0TxHdr[CCI_TX_HDR_WIDTH-1 : $bits(t_MDATA)],
                           t_MDATA'(c0_scoreboard_enqIdx) };
    assign deqTx = process_requests;
    assign qlp.C0TxRdValid = process_requests && c0_request_rdy;

    //
    // Responses.  Forward non-read respnoses directly.  Read data responses
    // come from the scoreboard.
    //
    assign afu_buf.C0RxWrValid = qlp.C0RxWrValid;
    assign afu_buf.C0RxCgValid = qlp.C0RxCgValid;
    assign afu_buf.C0RxUgValid = qlp.C0RxUgValid;
    assign afu_buf.C0RxIrValid = qlp.C0RxIrValid;

    // Is there a non-read response active?
    logic c0_non_rd_valid;
    assign c0_non_rd_valid = qlp.C0RxWrValid ||
                             qlp.C0RxCgValid ||
                             qlp.C0RxUgValid ||
                             qlp.C0RxIrValid;

    // Forward responses toward AFU as they become available in sorted order.
    // Non-read responses on the channel have priority since they are
    // unbuffered.
    assign afu_buf.C0RxRdValid = c0_scoreboard_notEmpty && ! c0_non_rd_valid;

    // Either forward the header from the QLP for non-read responses or
    // reconstruct the read response header.  The CCI-E header has the same
    // low bits as CCI-S so we always construct CCI-E and truncate when
    // in CCI-S mode.
    assign afu_buf.C0RxHdr =
        afu_buf.C0RxRdValid ?
            CCI_RX_HDR_WIDTH'(genRspHeaderCCIE(RdLineRsp, c0_scoreboard_mdata)) :
            qlp.C0RxHdr;


    // ====================================================================
    //
    //  Channel 1 (write)
    //
    // ====================================================================

    assign qlp.C1TxHdr = afu_buf.C1TxHdr;
    assign qlp.C1TxData = afu_buf.C1TxData;
    assign qlp.C1TxWrValid = afu_buf.C1TxWrValid && process_requests;
    assign qlp.C1TxIrValid = afu_buf.C1TxIrValid && process_requests;

    // Responses
    assign afu_buf.C1RxHdr = qlp.C1RxHdr;
    assign afu_buf.C1RxWrValid = qlp.C1RxWrValid;
    assign afu_buf.C1RxIrValid = qlp.C1RxIrValid;

endmodule // qa_shim_mux
