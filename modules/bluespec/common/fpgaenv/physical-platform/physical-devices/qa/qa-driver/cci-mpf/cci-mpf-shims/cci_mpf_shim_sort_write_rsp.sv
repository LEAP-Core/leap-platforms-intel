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
// Convert an unordered QLP interface port into a port with write responses
// coming in the same order as the original requests.
//

module cci_mpf_shim_sort_write_rsp
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,

    parameter N_SCOREBOARD_ENTRIES = 256,
    // Synchronize request channels if non-zero. Channel synchronization is
    // required to preserve load/store ordering.
    parameter SYNC_REQ_CHANNELS = 1
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_qlp qlp,

    // Connections toward user code.
    cci_mpf_if.to_afu afu
    );

    logic reset_n;
    assign reset_n = qlp.reset_n;
    assign afu.reset_n = qlp.reset_n;


    // ====================================================================
    //
    //  Scoreboard for tracking writes.
    //
    // ====================================================================

    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_SCOREBOARD_IDX;

    // Full signal that will come from the scoreboard used to sort responses.
    logic c1_scoreboard_notFull;

    t_SCOREBOARD_IDX c1_scoreboard_enqIdx;

    //
    // Coalesce write responses into vectors directed to the scoreboard
    //
    logic rx_wr_valid[0 : 1];
    assign rx_wr_valid[0] = qlp.c0Rx.wrValid;
    assign rx_wr_valid[1] = qlp.c1Rx.wrValid;

    t_SCOREBOARD_IDX rx_wr_idx[0 : 1];
    assign rx_wr_idx[0] = t_SCOREBOARD_IDX'(qlp.c0Rx.hdr);
    assign rx_wr_idx[1] = t_SCOREBOARD_IDX'(qlp.c1Rx.hdr);

    //
    // Sorted write responses
    //
    logic scoreboard_notEmpty[0 : 1];
    t_cci_mdata scoreboard_mdata[0 : 1];

    logic scoreboard_deq[0 : 1];
    assign scoreboard_deq[0] = afu.c0Rx.wrValid;
    assign scoreboard_deq[1] = afu.c1Rx.wrValid;


    cci_mpf_prim_scoreboard_dualport
      #(
        .N_ENTRIES(N_SCOREBOARD_ENTRIES),
        .N_DATA_BITS(0),
        .N_META_BITS(CCI_MDATA_WIDTH),
        .MIN_FREE_SLOTS(ALM_FULL_THRESHOLD)
        )
      c1_scoreboard(.clk,
                    .reset_n,

                    .enq_en(afu.C1TxWrValid),
                    // Mdata field is in the low bits of the request header
                    .enqMeta(t_cci_mdata'(afu.C1TxHdr)),
                    .notFull(c1_scoreboard_notFull),
                    .enqIdx(c1_scoreboard_enqIdx),

                    .enqData_en(rx_wr_valid),
                    .enqDataIdx(rx_wr_idx),
                    .enqData(),

                    .deq_en(scoreboard_deq),
                    .notEmpty(scoreboard_notEmpty),
                    .first(),
                    .firstMeta(scoreboard_mdata));


    // ====================================================================
    //
    //  The scoreboard is allocated with enough reserve space so that
    //  it honors the almost full semantics. No other buffering is
    //  required.
    //
    //  When SYNC_REQ_CHANNELS is true, Assert almost full if either
    //  request channel is filling so that the two channels stay
    //  synchronized. This maintains load/store order.
    //
    // ====================================================================

    logic c0_TxAlmFull;
    assign c0_TxAlmFull = qlp.c0TxAlmFull;

    logic c1_TxAlmFull;
    assign c1_TxAlmFull = qlp.c1TxAlmFull || ! c1_scoreboard_notFull;

    generate
        if (SYNC_REQ_CHANNELS == 0)
        begin
            assign afu.c0TxAlmFull = c0_TxAlmFull;
            assign afu.c1TxAlmFull = c1_TxAlmFull;
        end
        else
        begin
            assign afu.c0TxAlmFull = c0_TxAlmFull || c1_TxAlmFull;
            assign afu.c1TxAlmFull = c0_TxAlmFull || c1_TxAlmFull;
        end
    endgenerate


    // ====================================================================
    //
    //  Channel 0 (read).  Requests flow straight through.
    //
    // ====================================================================

    assign qlp.C0TxHdr = afu.C0TxHdr;
    assign qlp.C0TxRdValid = afu.C0TxRdValid;

    // Most responses are direct from the QLP.  Write responses flow
    // through the scoreboard.
    always_comb
    begin
        afu.c0Rx = qlp.c0Rx;

        // Write responses come from the scoreboard, though other responses
        // have priority since only the scoreboard is buffered.
        afu.c0Rx.wrValid = scoreboard_notEmpty[0] &&
                           ! qlp.c0Rx.rdValid &&
                           ! qlp.c0Rx.cfgValid &&
                           ! qlp.c0Rx.umsgValid &&
                           ! qlp.c0Rx.intrValid;

        afu.c0Rx.hdr =
            afu.c0Rx.wrValid ?
                genRspHeaderMPF(eRSP_WRLINE, scoreboard_mdata[0]) :
                qlp.c0Rx.hdr;
    end

    // ====================================================================
    //
    //  Channel 1 (write).
    //
    // ====================================================================

    // Forward requests toward the QLP.  Replace the Mdata entry with the
    // scoreboard index if the request is a write.  The original Mdata is
    // saved in the scoreboard and restored when the response is returned.
    assign qlp.C1TxHdr =
        afu.C1TxWrValid ?
            { afu.C1TxHdr[CCI_TX_HDR_WIDTH-1 : CCI_MDATA_WIDTH],
              t_cci_mdata'(c1_scoreboard_enqIdx) } :
            afu.C1TxHdr;

    assign qlp.C1TxData = afu.C1TxData;
    assign qlp.C1TxWrValid = afu.C1TxWrValid;
    assign qlp.C1TxIrValid = afu.C1TxIrValid;

    //
    // Responses.  Forward non-write responses directly.  Write responses
    // come from the scoreboard.
    //
    always_comb
    begin
        afu.c1Rx = qlp.c1Rx;

        // Write responses come from the scoreboard, though other responses
        // have priority since only the scoreboard is buffered.
        afu.c1Rx.wrValid = scoreboard_notEmpty[1] &&
                           ! qlp.c1Rx.intrValid;

        afu.c1Rx.hdr =
            afu.c1Rx.wrValid ?
                genRspHeaderMPF(eRSP_WRLINE, scoreboard_mdata[1]) :
                qlp.c1Rx.hdr;
    end

endmodule // cci_mpf_shim_sort_write_rsp

