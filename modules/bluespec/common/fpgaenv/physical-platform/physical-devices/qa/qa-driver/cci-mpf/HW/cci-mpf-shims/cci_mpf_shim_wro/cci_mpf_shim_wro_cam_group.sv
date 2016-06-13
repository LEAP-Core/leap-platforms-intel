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
// Manage a CAM associated with a group of requests that must be kept
// ordered.  Individual virtual channels are one example of a potential
// group.  In this case, distinct CCI virtual channels have no order
// guarantees, even when tracking write responses.  It thus makes sense
// to limit CAM sizes by tracking virtual channels as separate groups.
//

module cci_mpf_shim_wro_cam_group
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

    // Address hashes for requests at the head of afu_buf.  Two hashes
    // are exposed for each channel: the hashes of both the oldest (index 0)
    // and next oldest requests (index 1).  Exposing both is necessary
    // in the parent module, mostly to satisfy timing using registered
    // stale state instead of up-to-date combinational state.
    output logic [ADDRESS_HASH_BITS-1 : 0] c0_hash[0:1],
    output logic c0_hash_valid[0:1],
    output logic [ADDRESS_HASH_BITS-1 : 0] c1_hash[0:1],
    output logic c1_hash_valid[0:1],

    // Consume the oldest requests
    input  logic deqTx
    );

    cci_mpf_if afu_fifo (.clk);
    logic afu_deq;
    logic same_req_rw_addr_conflict;

    cci_mpf_shim_buffer_lockstep_afu
      #(
        .THRESHOLD(AFU_BUF_THRESHOLD),
        .REGISTER_OUTPUTS(1)
        )
      bufafu
       (
        .clk,
        .afu_raw,
        .afu_buf(afu_fifo),
        .deqTx(afu_deq)
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

    //
    // Register c0Tx and c1Tx.
    //
    t_if_cci_mpf_c0_Tx c0Tx;
    t_if_cci_mpf_c0_Tx c0Tx_q;
    t_if_cci_mpf_c1_Tx c1Tx;
    t_if_cci_mpf_c1_Tx c1Tx_q;

    // Move afu_fifo output to registers if the pipeline is moving or empty.
    logic move_to_regs;
    logic move_to_regs_q;
    assign move_to_regs = move_to_regs_q || ! (cci_mpf_c0TxIsValid(c0Tx) ||
                                               cci_mpf_c1TxIsValid(c1Tx));
    assign move_to_regs_q = deqTx || ! (cci_mpf_c0TxIsValid(c0Tx_q) ||
                                        cci_mpf_c1TxIsValid(c1Tx_q));

    // Dequeue from afu_fifo if the pipeline is moving and afu_fifo
    // isn't empty.
    assign afu_deq = move_to_regs &&
                     ! same_req_rw_addr_conflict &&
                     (cci_mpf_c0TxIsValid(afu_fifo.c0Tx) ||
                      cci_mpf_c1TxIsValid(afu_fifo.c1Tx));

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            c0Tx.valid <= 1'b0;
            c1Tx.valid <= 1'b0;
        end
        else if (deqTx && same_req_rw_addr_conflict)
        begin
            // Only the read was forwarded this cycle due to read/write conflict.
            c0Tx.valid <= 1'b0;
        end
        else if (move_to_regs)
        begin
            c0Tx <= afu_fifo.c0Tx;
            c1Tx <= afu_fifo.c1Tx;
        end
    end

    //
    // One more registered stage, adding a final transformation.  If the
    // two channels refer to the same address then send the read and then
    // the write in separate cycles.
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            c0Tx_q.valid <= 1'b0;
            c1Tx_q.valid <= 1'b0;

            c0_hash_valid[0] <= 1'b0;
            c1_hash_valid[0] <= 1'b0;
        end
        else if (move_to_regs_q)
        begin
            c0Tx_q <= c0Tx;

            c1Tx_q <= c1Tx;
            c1Tx_q.valid <= c1Tx.valid && ! same_req_rw_addr_conflict;

            c0_hash[0] <= c0_hash[1];
            c1_hash[0] <= c1_hash[1];
            c0_hash_valid[0] <= c0_hash_valid[1];
            c1_hash_valid[0] <= c1_hash_valid[1];
        end
    end

    // Does an incoming request have read and write to the same address?
    // Special case: delay the write.
    assign same_req_rw_addr_conflict =
        c0_hash_valid[1] && c1_hash_valid[1] && (c0_hash[1] == c1_hash[1]);

    assign afu_buf.c0Tx = c0Tx_q;
    assign afu_buf.c1Tx = c1Tx_q;


    // ====================================================================
    //
    // Calculate address hashes and register them in parallel with c0Tx
    // and c1Tx registers.
    //
    // ====================================================================

    typedef logic [ADDRESS_HASH_BITS-1 : 0] t_hash;

    // Start by expanding the addresses to 64 bits.
    logic [63:0] c0_req_addr;
    assign c0_req_addr = 64'(cci_mpf_c0_getReqAddr(afu_fifo.c0Tx.hdr));

    logic [63:0] c1_req_addr;
    assign c1_req_addr = 64'(cci_mpf_c1_getReqAddr(afu_fifo.c1Tx.hdr));

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            c0_hash_valid[1] <= 1'b0;
            c1_hash_valid[1] <= 1'b0;
        end
        else if (deqTx && same_req_rw_addr_conflict)
        begin
            // Only the read was forwarded this cycle due to read/write conflict.
            c0_hash_valid[1] <= 1'b0;
        end
        else if (move_to_regs)
        begin
            c0_hash[1] <= t_hash'(hash32(c0_req_addr[63:32] ^ c0_req_addr[31:0]));
            c0_hash_valid[1] <= cci_mpf_c0TxIsReadReq(afu_fifo.c0Tx);

            c1_hash[1] <= t_hash'(hash32(c1_req_addr[63:32] ^ c1_req_addr[31:0]));
            c1_hash_valid[1] <= cci_mpf_c1TxIsWriteReq(afu_fifo.c1Tx);
        end
    end

endmodule // cci_mpf_shim_wro_cam_group


