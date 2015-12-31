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
// Convert an unordered QLP interface port into a port with read responses
// coming in the same order as the original requests.
//


module cci_mpf_shim_sort_read_rsp
  #(
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


    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_SCOREBOARD_IDX;

    // Full signal that will come from the scoreboard used to sort responses.
    logic c0_scoreboard_notFull;


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
    assign c0_TxAlmFull = qlp.c0TxAlmFull || ! c0_scoreboard_notFull;

    logic c1_TxAlmFull;
    assign c1_TxAlmFull = qlp.c1TxAlmFull;

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
    //  Channel 0 (read)
    //
    // ====================================================================

    t_SCOREBOARD_IDX c0_scoreboard_enqIdx;

    logic c0_scoreboard_notEmpty;
    t_cci_mdata c0_scoreboard_mdata;

    t_cci_cldata c0_scoreboard_outData;

    cci_mpf_prim_scoreboard
      #(
        .N_ENTRIES(N_SCOREBOARD_ENTRIES),
        .N_DATA_BITS(CCI_CLDATA_WIDTH),
        .N_META_BITS(CCI_MDATA_WIDTH),
        .MIN_FREE_SLOTS(CCI_ALMOST_FULL_THRESHOLD)
        )
      c0_scoreboard(.clk,
                    .reset_n,

                    .enq_en(afu.C0TxRdValid),
                    // Mdata field is in the low bits of the request header
                    .enqMeta(t_cci_mdata'(afu.C0TxHdr)),
                    .notFull(c0_scoreboard_notFull),
                    .enqIdx(c0_scoreboard_enqIdx),

                    .enqData_en(qlp.c0Rx.rdValid),
                    .enqDataIdx(t_SCOREBOARD_IDX'(qlp.c0Rx.hdr)),
                    .enqData(qlp.c0Rx.data),

                    .deq_en(afu.c0Rx.rdValid),
                    .notEmpty(c0_scoreboard_notEmpty),
                    .first(c0_scoreboard_outData),
                    .firstMeta(c0_scoreboard_mdata));

    // Forward requests toward the QLP.  Replace the Mdata entry with the
    // scoreboard index.  The original Mdata is saved in the scoreboard
    // and restored when the response is returned.
    assign qlp.C0TxHdr = { afu.C0TxHdr[CCI_MPF_TX_MEMHDR_WIDTH-1 : CCI_MDATA_WIDTH],
                           t_cci_mdata'(c0_scoreboard_enqIdx) };
    assign qlp.C0TxRdValid = afu.C0TxRdValid;

    logic c0_non_rd_valid;

    //
    // Responses.  Forward non-read responses directly.  Read data responses
    // come from the scoreboard.
    //
    always_comb
    begin
        afu.c0Rx = qlp.c0Rx;
        afu.c0Rx.data = c0_scoreboard_outData;

        // Is there a non-read response active?
        c0_non_rd_valid = qlp.c0Rx.wrValid ||
                          qlp.c0Rx.cfgValid ||
                          qlp.c0Rx.umsgValid ||
                          qlp.c0Rx.intrValid;

        // Forward responses toward AFU as they become available in sorted order.
        // Non-read responses on the channel have priority since they are
        // unbuffered.
        afu.c0Rx.rdValid = c0_scoreboard_notEmpty && ! c0_non_rd_valid;

        // Either forward the header from the QLP for non-read responses or
        // reconstruct the read response header.  The CCI-E header has the same
        // low bits as CCI-S so we always construct CCI-E and truncate when
        // in CCI-S mode.
        afu.c0Rx.hdr =
            afu.c0Rx.rdValid ?
                genRspHeaderMPF(eRSP_RDLINE, c0_scoreboard_mdata) :
                qlp.c0Rx.hdr;
    end


    // ====================================================================
    //
    //  Channel 1 (write).  Requests flow straight through.
    //
    // ====================================================================

    assign qlp.C1TxHdr = afu.C1TxHdr;
    assign qlp.C1TxData = afu.C1TxData;
    assign qlp.C1TxWrValid = afu.C1TxWrValid;
    assign qlp.C1TxIrValid = afu.C1TxIrValid;

    // Responses
    assign afu.c1Rx = qlp.c1Rx;

endmodule // cci_mpf_shim_sort_read_rsp


