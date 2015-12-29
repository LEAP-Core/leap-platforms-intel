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
// Convert a single QLP interface port into a multiplexed pair of ports
// with round-robin arbitration on the requests.  Responses are routed
// back to the port that generated the request.
//


module cci_mpf_shim_mux
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,
    //
    // This MUX requires that one bit be reserved for message routing in the
    // Mdata field.  This reserved bit allows the MUX to route responses with
    // simple logic and without having to allocate extra storage to preserve
    // Mdata bits.  The reserved bit is configurable using RESERVED_MDATA_IDX.
    // The instantiation point must pick a bit -- the default value is
    // purposely illegal in order to force a decision.  The reserved bit
    // must be 0 on requests from the AFU ports and is guaranteed to be 0
    // in responses to the AFU ports.
    //
    parameter RESERVED_MDATA_IDX = -1
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_qlp qlp,

    // Connections toward user code.
    cci_mpf_if.to_afu afus[0:1]
    );

    //
    // The current code supports multiplexing among a pair of clients and
    // NUM_AFU_PORTS must be 2.  Supporting more than two would require
    // a parameter to set the number of ports, a more complex arbiter and
    // more logic for managing a multi-bit index in Mdata.
    //
    localparam NUM_AFU_PORTS = 2;
    localparam AFU_PORTS_RADIX = $clog2(NUM_AFU_PORTS);

    logic reset_n;
    assign reset_n = qlp.reset_n;


    // ====================================================================
    //
    // Instantiate a buffer on the AFU request ports, making them latency
    // insensitive.
    //
    // ====================================================================

    cci_mpf_if
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      afu_buf[0:1] (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqC0Tx[0:1];
    logic deqC1Tx[0:1];

    genvar p;
    generate
        for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
        begin : genBuffers

            cci_mpf_shim_buffer_afu
              #(
                .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
                .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
                .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
                .CCI_TAG_WIDTH(CCI_TAG_WIDTH),
                .ENABLE_C0_BYPASS(1)
                )
              b
                (
                 .clk,
                 .afu_raw(afus[p]),
                 .afu_buf(afu_buf[p]),
                 .deqC0Tx(deqC0Tx[p]),
                 .deqC1Tx(deqC1Tx[p])
                 );

            //
            // Almost full signals in the buffered input are ignored --
            // replaced by deq signals and the buffer state.  Set them
            // to 1 to be sure they are ignored.
            //
            assign afu_buf[p].C0TxAlmFull = 1'b1;
            assign afu_buf[p].C1TxAlmFull = 1'b1;
        end
    endgenerate


    // ====================================================================
    //
    // Arbitration.
    //
    // ====================================================================

    // Round-robin arbitration.  Last winner index recorded here.
    logic [AFU_PORTS_RADIX-1 : 0] last_c0_winner_idx;
    logic [AFU_PORTS_RADIX-1 : 0] last_c1_winner_idx;

    // Is either AFU making a request?
    logic [NUM_AFU_PORTS-1 : 0] c0_request;
    logic [NUM_AFU_PORTS-1 : 0] c1_request;

    generate
        for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
        begin : channelRequests
            //
            // Are there incoming requests?
            //

            assign c0_request[p] = afu_buf[p].C0TxRdValid;

            assign c1_request[p] = (afu_buf[p].C1TxWrValid ||
                                    afu_buf[p].C1TxIrValid);
        end
    endgenerate

    // Pick winners for each request channel.
    logic [AFU_PORTS_RADIX-1 : 0] c0_winner_idx;
    logic [AFU_PORTS_RADIX-1 : 0] c1_winner_idx;

    // Round-robin arbitration among two clients is trivial
    assign c0_winner_idx = c0_request[1] && (! c0_request[0] ||
                                             (last_c0_winner_idx == 0));
    assign c1_winner_idx = c1_request[1] && (! c1_request[0] ||
                                             (last_c1_winner_idx == 0));

    logic check_hdr0;
    logic check_hdr1;

    // Record the winners
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            last_c0_winner_idx <= 0;
            last_c1_winner_idx <= 0;
        end
        else
        begin
            // Only update the winner if there was a request.
            if (|c0_request && ! qlp.C0TxAlmFull)
            begin
                last_c0_winner_idx <= c0_winner_idx;

                assert(check_hdr0 == 0) else
                    $fatal("cci_mpf_shim_mux.sv: AFU C0 Mdata[%d] must be zero", RESERVED_MDATA_IDX);
            end

            if (|c1_request && ! qlp.C1TxAlmFull)
            begin
                last_c1_winner_idx <= c1_winner_idx;

                assert(check_hdr1 == 0) else
                    $fatal("cci_mpf_shim_mux.sv: AFU C1 Mdata[%d] must be zero", RESERVED_MDATA_IDX);
            end
        end
    end


    // ====================================================================
    //
    //  Route the chosen AFU request toward the QLP port.
    //
    // ====================================================================

    always_ff @(posedge clk)
    begin
        assert ((RESERVED_MDATA_IDX > 0) && (RESERVED_MDATA_IDX < CCI_TAG_WIDTH)) else
            $fatal("cci_mpf_shim_mux.sv: Illegal RESERVED_MDATA_IDX value: %d", RESERVED_MDATA_IDX);
    end

    //
    // tagRequest --
    //   Update a request's Mdata field with the index of the AFU from which
    //   the request came.
    //
    function automatic [CCI_TX_HDR_WIDTH-1:0] tagRequest;
        input [CCI_TX_HDR_WIDTH-1:0] header;
        input afu_idx;

        tagRequest = header;
        tagRequest[RESERVED_MDATA_IDX] = afu_idx;
    endfunction

    always_comb
    begin
        if (qlp.C0TxAlmFull || ! (|c0_request))
        begin
            // No request
            qlp.C0TxHdr = 'x;
            qlp.C0TxRdValid = 1'b0;
            check_hdr0 = 'x;
        end
        else if (c0_winner_idx == 0)
        begin
            // Mux port 0 wins
            qlp.C0TxHdr = tagRequest(afu_buf[0].C0TxHdr, 0);
            qlp.C0TxRdValid = afu_buf[0].C0TxRdValid;
            check_hdr0 = afu_buf[0].C0TxHdr[RESERVED_MDATA_IDX];
        end
        else
        begin
            // Mux port 1 wins
            qlp.C0TxHdr = tagRequest(afu_buf[1].C0TxHdr, 1);
            qlp.C0TxRdValid = afu_buf[1].C0TxRdValid;
            check_hdr0 = afu_buf[1].C0TxHdr[RESERVED_MDATA_IDX];
        end

        if (qlp.C1TxAlmFull || ! (|c1_request))
        begin
            // No request
            qlp.C1TxHdr = 'x;
            qlp.C1TxData = 'x;
            qlp.C1TxWrValid = 1'b0;
            qlp.C1TxIrValid = 1'b0;
            check_hdr1 = 'x;
        end
        else if (c1_winner_idx == 0)
        begin
            // Mux port 0 wins
            qlp.C1TxHdr = tagRequest(afu_buf[0].C1TxHdr, 0);
            qlp.C1TxData = afu_buf[0].C1TxData;
            qlp.C1TxWrValid = afu_buf[0].C1TxWrValid;
            qlp.C1TxIrValid = afu_buf[0].C1TxIrValid;
            check_hdr1 = afu_buf[0].C1TxHdr[RESERVED_MDATA_IDX];
        end
        else
        begin
            // Mux port 1 wins
            qlp.C1TxHdr = tagRequest(afu_buf[1].C1TxHdr, 1);
            qlp.C1TxData = afu_buf[1].C1TxData;
            qlp.C1TxWrValid = afu_buf[1].C1TxWrValid;
            qlp.C1TxIrValid = afu_buf[1].C1TxIrValid;
            check_hdr1 = afu_buf[1].C1TxHdr[RESERVED_MDATA_IDX];
        end
    end

    // Propagate reset and fire deq when appropriate.
    generate
        for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
        begin : ctrlBlock
            assign afu_buf[p].reset_n = qlp.reset_n;

            // Dequeue if there was a request and the source won arbitration.
            assign deqC0Tx[p] = c0_request[p] && (c0_winner_idx == p) && ! qlp.C0TxAlmFull;
            assign deqC1Tx[p] = c1_request[p] && (c1_winner_idx == p) && ! qlp.C1TxAlmFull;
        end
    endgenerate


    // ====================================================================
    //
    //  Route the QLP responses back to the proper AFU port
    //
    // ====================================================================

    //
    // untagRequest --
    //   Restore the Mdata field used by this MUX before forwarding to the AFU.
    //   The field was required to be zero, so restoring it is easy.
    //
    function automatic [CCI_RX_HDR_WIDTH-1:0] untagRequest;
        input [CCI_RX_HDR_WIDTH-1:0] header;
        input isResponse;

        untagRequest = header;
        if (isResponse)
        begin
            untagRequest[RESERVED_MDATA_IDX] = 0;
        end
    endfunction

    // To which AFU are the channel responses going?  We will route the
    // data and header to both unconditionally and use the control bits
    // to control destination.
    logic c0_rsp_idx;
    assign c0_rsp_idx = qlp.C0RxHdr[RESERVED_MDATA_IDX];
    logic c1_rsp_idx;
    assign c1_rsp_idx = qlp.C1RxHdr[RESERVED_MDATA_IDX];

    generate
        for (p = 0; p < NUM_AFU_PORTS; p = p + 1)
        begin : respRouting
            assign afu_buf[p].C0RxHdr = untagRequest(qlp.C0RxHdr,
                                                     qlp.C0RxWrValid ||
                                                     qlp.C0RxRdValid);

            assign afu_buf[p].C0RxData = qlp.C0RxData;
            assign afu_buf[p].C0RxWrValid = qlp.C0RxWrValid && (p[0] == c0_rsp_idx);
            assign afu_buf[p].C0RxRdValid = qlp.C0RxRdValid && (p[0] == c0_rsp_idx);
            // Host-generated requests are broadcasts
            assign afu_buf[p].C0RxCgValid = qlp.C0RxCgValid;
            assign afu_buf[p].C0RxUgValid = qlp.C0RxUgValid;
            assign afu_buf[p].C0RxIrValid = qlp.C0RxIrValid;

            assign afu_buf[p].C1RxHdr = untagRequest(qlp.C1RxHdr,
                                                     qlp.C1RxWrValid);

            assign afu_buf[p].C1RxWrValid = qlp.C1RxWrValid && (p[0] == c1_rsp_idx);
            assign afu_buf[p].C1RxIrValid = qlp.C1RxIrValid;
        end
    endgenerate

endmodule // cci_mpf_shim_mux

