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

`include "cci_mpf_if.vh"


//
// Detect the last response corresponding to multi-beat reads and writes.
// Multiple MPF modules depend on seeing EOP to deallocate heap entries.
//
// Write responses are coalesced into a single packed response, simplifying
// logic in upstream modules.
//
// Read responses are decoared with an end of packet flag (EOP).  The
// The CCI response structures don't have an explicit place to store EOP
// and the location may change in the future.  Use the test function
// cci_mpf_c0Rx_isEOP().
//

module cci_mpf_shim_detect_eop
  #(
    // Maximum number of in-flight reads and in-flight writes.  MPF's
    // shim composition rules require that requests have temporally unique
    // values in the low bits of Mdata.  This module generates tags
    // taking advantage of indices constructed from unique Mdata values.
    parameter MAX_ACTIVE_REQS = 128
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu
    );

    logic reset;
    assign reset = fiu.reset;
    assign afu.reset = fiu.reset;

    // Index of a request
    localparam N_REQ_IDX_BITS = $clog2(MAX_ACTIVE_REQS);
    typedef logic [N_REQ_IDX_BITS-1 : 0] t_req_idx;

    logic rd_rsp_mon_rdy;
    logic wr_rsp_mon_rdy;

    assign afu.c0TxAlmFull = fiu.c0TxAlmFull || ! rd_rsp_mon_rdy;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull || ! wr_rsp_mon_rdy;


    // ====================================================================
    //
    //  Allocate storage for tracking response counts
    //
    // ====================================================================


    // ====================================================================
    //
    //  Channel 0 (read) -- No action.
    //
    // ====================================================================

    //
    // Monitor flow of requests and responses.
    //

    t_cci_clNum rd_rsp_packet_len;
    logic rd_rsp_pkt_eop;

    cci_mpf_shim_detect_eop_track_flits
      #(
        .MAX_ACTIVE_REQS(MAX_ACTIVE_REQS)
        )
      c0_tracker
       (
        .clk,
        .reset,
        .rdy(rd_rsp_mon_rdy),

        .req_en(cci_mpf_c0TxIsReadReq(afu.c0Tx)),
        .reqIdx(t_req_idx'(afu.c0Tx.hdr.base.mdata)),
        .reqLen(afu.c0Tx.hdr.base.cl_len),

        .rsp_en(cci_c0Rx_isReadRsp(fiu.c0Rx)),
        .rspIdx(t_req_idx'(fiu.c0Rx.hdr.mdata)),
        .rspIsPacked(1'b0),

        .pkt_eop(rd_rsp_pkt_eop),
        .rspLen(rd_rsp_packet_len)
        );


    //
    // Requests
    //
    assign fiu.c0Tx = afu.c0Tx;


    //
    // Responses
    //
    always_ff @(posedge clk)
    begin
        afu.c0Rx <= cci_mpf_c0Rx_updEOP(fiu.c0Rx, rd_rsp_pkt_eop);
    end


    // ====================================================================
    //
    //  Channel 1 (write) -- Merge multi-beat responses.
    //
    // ====================================================================

    //
    // Monitor flow of requests and responses.
    //

    t_cci_clNum wr_rsp_packet_len;
    logic wr_rsp_pkt_eop;

    cci_mpf_shim_detect_eop_track_flits
      #(
        .MAX_ACTIVE_REQS(MAX_ACTIVE_REQS)
        )
      c1_tracker
       (
        .clk,
        .reset,
        .rdy(wr_rsp_mon_rdy),

        .req_en(cci_mpf_c1TxIsWriteReq(afu.c1Tx)),
        .reqIdx(t_req_idx'(afu.c1Tx.hdr.base.mdata)),
        .reqLen(afu.c1Tx.hdr.base.cl_len),

        .rsp_en(cci_c1Rx_isWriteRsp(fiu.c1Rx)),
        .rspIdx(t_req_idx'(fiu.c1Rx.hdr.mdata)),
        .rspIsPacked(fiu.c1Rx.hdr.format),

        .pkt_eop(wr_rsp_pkt_eop),
        .rspLen(wr_rsp_packet_len)
        );


    //
    // Requests
    //
    assign fiu.c1Tx = afu.c1Tx;


    //
    // Responses
    //
    always_ff @(posedge clk)
    begin
        afu.c1Rx <= fiu.c1Rx;

        // If wr_rsp_pkt_eop is 0 then this flit is a write response and it
        // isn't the end of the packet.  Drop it.  The response will be
        // merged into a single flit.
        if (! wr_rsp_pkt_eop)
        begin
            afu.c1Rx.rspValid <= 1'b0;
        end

        // Merge write responses for a packet into single response.
        // This code simply assumes the flit is the end of the packet.
        // The code above will clear the valid bit if it isn't the end.
        if (cci_c1Rx_isWriteRsp(fiu.c1Rx))
        begin
            afu.c1Rx.hdr.format <= 1'b1;
            afu.c1Rx.hdr.cl_num <= wr_rsp_packet_len;
        end
    end


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign fiu.c2Tx = afu.c2Tx;

endmodule // cci_mpf_shim_detect_eop


//
// Control code for monitoring requests and responses on a channel and
// detecting the flit that is the last response for a packet.
//
module cci_mpf_shim_detect_eop_track_flits
  #(
    MAX_ACTIVE_REQS = 128
    )
   (
    input  logic clk,
    input  logic reset,
    output logic rdy,

    // New request to track
    input  logic req_en,
    input  logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] reqIdx,
    input  t_cci_clNum reqLen,

    // New response
    input  logic rsp_en,
    input  logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] rspIdx,
    input  logic rspIsPacked,

    // Is response the end of the packet?
    output logic pkt_eop,
    // Full length of the flit's packet
    output t_cci_clNum rspLen
    );

    // Packet size of outstanding requests.  Separating this from the count
    // of responses avoids dealing with multiple writers to either memory.
    t_cci_clNum packet_len[0 : MAX_ACTIVE_REQS-1] /* synthesis ramstyle = "MLAB, no_rw_check" */;

    always_ff @(posedge clk)
    begin
        if (req_en)
        begin
            packet_len[reqIdx] <= reqLen;
        end
    end

    //
    // Responses
    //

    //
    // Count responses per packet in distributed RAM
    //
    t_cci_clNum rcvd_cnt;
    t_cci_clNum rcvd_cnt_upd;
    logic rcvd_wen;

    // Target length of the response's full packet
    assign rspLen = packet_len[rspIdx];

    cci_mpf_prim_lutram_init
      #(
        .N_ENTRIES(MAX_ACTIVE_REQS),
        .N_DATA_BITS($bits(t_cci_clNum))
        )
      wr_rsp_cnt
       (
        .clk,
        .reset,
        .rdy,
        .raddr(rspIdx),
        .rdata(rcvd_cnt),
        .waddr(rspIdx),
        .wen(rsp_en),
        .wdata(rcvd_cnt_upd)
        );

    // Update count as packets are received
    always_comb
    begin
        pkt_eop = 1'b1;
        rcvd_cnt_upd = 'x;

        if (rsp_en)
        begin
            if (rspIsPacked || (rcvd_cnt == rspLen))
            begin
                // Only one response or last packet.  Done!
                rcvd_cnt_upd = t_cci_clNum'(0);
            end
            else
            begin
                // One flit received.  Keep counting.
                rcvd_cnt_upd = rcvd_cnt + t_cci_clNum'(1);
                pkt_eop = 1'b0;
            end
        end
    end

endmodule // cci_mpf_shim_detect_eop_track_flits
