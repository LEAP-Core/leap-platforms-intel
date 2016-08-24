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
`include "cci_mpf_prim_hash.vh"


//
// This module is the head of a channel's pipeline.  It serves two
// purposes: add flow control to the request pipeline and hash incoming
// addresses.
//
module cci_mpf_shim_wro_buffer_and_hash
  #(
    parameter AFU_BUF_THRESHOLD = CCI_TX_ALMOST_FULL_THRESHOLD,
    parameter ADDRESS_HASH_BITS = 0
    )
   (
    input  logic clk,

    // Connection to AFU
    cci_mpf_if.to_afu afu_raw,
    // Buffered connection to AFU
    cci_mpf_if.to_fiu afu_buf,

    // Address hashes for requests at the head of afu_buf.  Two sets are
    // exported because of pipelining in this module.  Index 0 always
    // corresponds to the oldest request.
    output logic [ADDRESS_HASH_BITS-1 : 0] c0_hash[0:1],
    input  logic c0_hash_conflicts[0:1],
    output logic [ADDRESS_HASH_BITS-1 : 0] c1_hash[0:1],
    input  logic c1_hash_conflicts[0:1],

    // Consume the oldest requests
    input  logic c0_deqTx,
    input  logic c1_deqTx,

    //
    // Not empty signals are used to figure out whether the pipeline is
    // completely idle.  This is required for blocking for write fences.
    //

    // Is the c1 buffer here completely empty?
    output logic c1_buf_notEmpty,

    // Is the downstream WRO c1 (write request) pipeline empty?
    input  logic c1_pipe_notEmpty,

    cci_mpf_csrs.wro csrs
    );

    cci_mpf_if afu_fifo (.clk);
    logic afu_deq;
    logic same_req_rw_addr_conflict;
    logic block_new_requests;

    // The lockstep AFU manages QoS for each channel by throttling traffic
    // using the almost full wires.  Making N_ENTRIES larger than normal
    // gives the algorithm some space for throughput management.
    localparam AFU_BUF_ENTRIES = AFU_BUF_THRESHOLD + (AFU_BUF_THRESHOLD / 2);

    cci_mpf_shim_buffer_lockstep_afu
      #(
        .THRESHOLD(AFU_BUF_THRESHOLD),
        .N_ENTRIES(AFU_BUF_ENTRIES),
        .REGISTER_OUTPUT(1)
        )
      bufafu
       (
        .clk,
        .afu_raw,
        .afu_buf(afu_fifo),
        .deqTx(afu_deq),

        // QoS settings
        .setqos(csrs.wro_ctrl_valid),
        .setqos_enable(csrs.wro_ctrl[0]),
        .setqos_beat_delta_threshold(csrs.wro_ctrl[15:8]),
        .setqos_min_beat_threshold(csrs.wro_ctrl[23:16])
        );

    logic reset;
    assign reset = afu_buf.reset;
    assign afu_fifo.reset = afu_buf.reset;

    // All but c0Tx and c1Tx are wires
    assign afu_buf.c2Tx = afu_fifo.c2Tx;
    assign afu_fifo.c0TxAlmFull = afu_buf.c0TxAlmFull;
    assign afu_fifo.c1TxAlmFull = afu_buf.c1TxAlmFull;

    assign afu_fifo.c0Rx = afu_buf.c0Rx;
    assign afu_fifo.c1Rx = afu_buf.c1Rx;


    // ====================================================================
    //
    //  Hash addresses as they arrive and store them in a FIFO so they
    //  arrive along with afu_fifo above.
    //
    // ====================================================================

    typedef logic [ADDRESS_HASH_BITS-1 : 0] t_hash;

    // Just hash the low 32 bits.  The high bits are unlikely to vary during
    // a relevant region.
    logic [31:0] c0_req_addr;
    assign c0_req_addr = 32'(cci_mpf_c0_getReqAddr(afu_raw.c0Tx.hdr));

    logic [31:0] c1_req_addr;
    assign c1_req_addr = 32'(cci_mpf_c1_getReqAddr(afu_raw.c1Tx.hdr));

    t_hash c0_hash_next;
    logic c0_hash_next_en;
    t_hash c1_hash_next;
    logic c1_hash_next_en;

    function automatic t_hash hashAddr(t_cci_clAddr addr);
        return t_hash'(hash32(addr));
    endfunction

    always_ff @(posedge clk)
    begin
        c0_hash_next <= hashAddr(c0_req_addr);
        c0_hash_next_en <= cci_mpf_c0TxIsValid(afu_raw.c0Tx);

        c1_hash_next <= hashAddr(c1_req_addr);
        c1_hash_next_en <= cci_mpf_c1TxIsValid(afu_raw.c1Tx);

        if (reset)
        begin
            c0_hash_next_en <= 1'b0;
            c1_hash_next_en <= 1'b0;
        end
    end

    t_hash c0_hash_fifo;
    logic c0_hash_fifo_notEmpty;
    t_hash c1_hash_fifo;
    logic c1_hash_fifo_notEmpty;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(ADDRESS_HASH_BITS),
        .N_ENTRIES(AFU_BUF_ENTRIES),
        .REGISTER_OUTPUT(1)
        )
      c0_hash_buf
       (.clk,
        .reset,
        .enq_data(c0_hash_next),
        .enq_en(c0_hash_next_en),
        .notFull(),
        .almostFull(),
        .first(c0_hash_fifo),
        .deq_en(afu_deq && cci_mpf_c0TxIsValid(afu_fifo.c0Tx)),
        .notEmpty(c0_hash_fifo_notEmpty)
        );

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(ADDRESS_HASH_BITS),
        .N_ENTRIES(AFU_BUF_ENTRIES),
        .REGISTER_OUTPUT(1)
        )
      c1_hash_buf
       (.clk,
        .reset,
        .enq_data(c1_hash_next),
        .enq_en(c1_hash_next_en),
        .notFull(),
        .almostFull(),
        .first(c1_hash_fifo),
        .deq_en(afu_deq && cci_mpf_c1TxIsValid(afu_fifo.c1Tx)),
        .notEmpty(c1_hash_fifo_notEmpty)
        );


    // Pass the buffered hash to the main WRO pipeline to test it against
    // current activity.
    assign c0_hash[1] = c0_hash_fifo;
    assign c1_hash[1] = c1_hash_fifo;


    // ====================================================================
    //
    //  Manage flow of requests out of the buffer and toward the main
    //  WRO pipeline.
    //
    // ====================================================================

    //
    // Request data flowing through filtering pipeline
    //
    t_if_cci_mpf_c0_Tx c0Tx;
    t_if_cci_mpf_c1_Tx c1Tx;

    // Delay writes when they conflict with a read in the same buffer position
    logic tx_addr_conflict;

    // New requests can't be forwarded out of this module if they conflict
    // with other requests in main WRO pipeline.
    logic c0_pipe_conflicts;
    logic c1_pipe_conflicts;

    logic block_for_wrfence;
    assign block_for_wrfence = cci_mpf_c1TxIsWriteFenceReq_noCheckValid(c1Tx) &&
                               c1_pipe_notEmpty;

    assign afu_buf.c0Tx = cci_mpf_c0TxMaskValids(c0Tx, ! c0_pipe_conflicts);
    assign afu_buf.c1Tx = cci_mpf_c1TxMaskValids(c1Tx, ! c1_pipe_conflicts);

    // Forward new state to the request pipeline if space is available.
    assign afu_deq = (c0_deqTx || ! cci_mpf_c0TxIsValid(c0Tx)) &&
                     (c1_deqTx || ! cci_mpf_c1TxIsValid(c1Tx)) &&
                     ((cci_mpf_c0TxIsValid(afu_fifo.c0Tx) && c0_hash_fifo_notEmpty) ||
                      (cci_mpf_c1TxIsValid(afu_fifo.c1Tx) && c1_hash_fifo_notEmpty));

    // Do the read and write address conflict in the new request?
    logic afu_fifo_addr_conflict;
    assign afu_fifo_addr_conflict = (c0_hash_fifo == c1_hash_fifo) &&
                                    cci_mpf_c0TxIsReadReq(afu_fifo.c0Tx) &&
                                    cci_mpf_c1TxIsWriteReq(afu_fifo.c1Tx);

    // Update the output pipeline
    always_ff @(posedge clk)
    begin
        // Channel 0 (read) consumed?
        if (c0_deqTx)
        begin
            c0Tx <= cci_mpf_c0Tx_clearValids();
            // Clear read/write conflict when read completes
            tx_addr_conflict <= 1'b0;
        end

        // Channel 1 (write) consumed?
        if (c1_deqTx)
        begin
            c1Tx <= cci_mpf_c1Tx_clearValids();
        end

        // Update pipe conflicts in case the oldest entry is waiting for
        // existing requests to clear out of the pipeline.
        c0_pipe_conflicts <= c0_hash_conflicts[0];
        c1_pipe_conflicts <=
            c1_hash_conflicts[0] ||
            // Hold write for conflicting read in c0Tx?
            tx_addr_conflict ||
            // Hold write fence until all requests have exited WRO?
            block_for_wrfence;

        if (afu_deq)
        begin
            c0Tx <= afu_fifo.c0Tx;
            if (c0_hash_fifo_notEmpty)
            begin
                c0_hash[0] <= c0_hash_fifo;
            end

            c1Tx <= afu_fifo.c1Tx;
            if (c1_hash_fifo_notEmpty && cci_mpf_c1TxIsWriteReq(afu_fifo.c1Tx))
            begin
                c1_hash[0] <= c1_hash_fifo;
            end

            tx_addr_conflict <= afu_fifo_addr_conflict;

            // Use the pipeline conflict for the new requests.  The request
            // that may just have been released must also be considered.
            c0_pipe_conflicts <=
                (c0_hash_conflicts[1] === 1'b1) ||
                (c1_hash[0] === c0_hash[1]) || (c0_hash[0] === c0_hash[1]);

            c1_pipe_conflicts <=
                (c1_hash_conflicts[1] === 1'b1) ||
                (c0_hash[0] === c1_hash[1]) || (c1_hash[0] === c1_hash[1]) ||
                afu_fifo_addr_conflict ||
                cci_mpf_c1TxIsWriteFenceReq(afu_fifo.c1Tx);
        end

        if (reset)
        begin
            c0Tx <= cci_mpf_c0Tx_clearValids();
            c1Tx <= cci_mpf_c1Tx_clearValids();
            tx_addr_conflict <= 1'b0;
            c0_hash[0] <= 0;
            c1_hash[0] <= 0;
        end
    end

endmodule // cci_mpf_shim_wro_cam_group
