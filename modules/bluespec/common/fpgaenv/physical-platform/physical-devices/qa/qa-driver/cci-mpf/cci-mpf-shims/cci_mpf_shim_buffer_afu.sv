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
// This is more a primitive shim than a full fledged shim.  It takes an
// AFU-side raw connection (wires) and adds latency insensitive buffering
// on the read/write request wires.  Most shims will instantiate this
// shim on the AFU-side connections in order to eliminate loops in the
// computation of the AFU-side almost full signals.
//

module cci_mpf_shim_buffer_afu
  #(
    parameter N_ENTRIES = CCI_ALMOST_FULL_THRESHOLD + 2,
    parameter THRESHOLD = CCI_ALMOST_FULL_THRESHOLD,
    // If nonzero, incoming requests from afu_raw on channel 0 may bypass
    // the FIFO and be received in the same cycle through afu_buf.  This
    // is offered only on channel 0.  Bypassing is not offered on channel
    // 1 both because stores are less latency sensitive and because the
    // cost of a bypass MUX on the line-sized store data is too high.
    parameter ENABLE_C0_BYPASS = 0
    )
   (
    input  logic clk,

    // Raw unbuffered connection.  This is the AFU-side connection of the
    // parent module.
    cci_mpf_if.to_afu afu_raw,

    // Generated buffered connection.  The confusing interface direction
    // arises because the shim is an interposer on the AFU side of a
    // standard shim.
    cci_mpf_if.to_fiu afu_buf,

    // Dequeue signals combined with the buffering make the buffered interface
    // latency insensitive.  Requests sit in the buffers unless explicitly
    // removed.
    input logic deqC0Tx,
    input logic deqC1Tx
    );

    assign afu_raw.reset_n = afu_buf.reset_n;

    //
    // Rx wires pass through toward the AFU.  They are latency sensitive
    // since the CCI provides no back pressure.
    //
    assign afu_raw.c0Rx = afu_buf.c0Rx;
    assign afu_raw.c1Rx = afu_buf.c1Rx;


    // ====================================================================
    //
    // Channel 0 Tx buffer.
    //
    //   The buffer triggers c0TxAlmFull when there are 4 or fewer slots
    //   available, as required by the CCI specification.  Unlike the
    //   usual CCI request interface, movement through the pipeline is
    //   explicit.  The code that instantiates this buffer must dequeue
    //   the head of the FIFO using deqC0Tx in order to consume a request.
    //
    // ====================================================================

    localparam C0TX_BITS = CCI_MPF_TX_MEMHDR_WIDTH;

    t_cci_mpf_ReqMemHdr c0_fifo_first;
    logic c0_fifo_notEmpty;
    logic c0_fifo_enq;
    logic c0_fifo_deq;

    // If the bypass is enabled on channel 0 then route around the FIFO if
    // the FIFO is currently empty and the logic connected to afu_buf consumes
    // a new message from afu_raw immediately.
    generate
        if (ENABLE_C0_BYPASS == 0)
        begin
            // No bypass.  All messages flow through the FIFO.
            assign afu_buf.c0Tx =
                cci_mpf_genC0TxReadReq(c0_fifo_first, c0_fifo_notEmpty);

            assign c0_fifo_enq = afu_raw.c0Tx.rdValid;
            assign c0_fifo_deq = deqC0Tx;
        end
        else
        begin
            // Bypass FIFO when possible.
            assign afu_buf.c0Tx =
                c0_fifo_notEmpty ?
                    cci_mpf_genC0TxReadReq(c0_fifo_first, 1) :
                    afu_raw.c0Tx;

            // Enq to the FIFO if a new request has arrived and it wasn't
            // consumed immediately through afu_buf.
            assign c0_fifo_enq =
                afu_raw.c0Tx.rdValid && (c0_fifo_notEmpty || ! deqC0Tx);

            assign c0_fifo_deq = deqC0Tx && c0_fifo_notEmpty;
        end
    endgenerate

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(C0TX_BITS),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      c0_fifo(.clk,
              .reset_n(afu_buf.reset_n),

              .enq_data(afu_raw.c0Tx.hdr),
              // c0Tx.rdValid is the only incoming valid bit.  Map it through
              // as enq here and notEmpty below.
              .enq_en(c0_fifo_enq),
              .notFull(),
              .almostFull(afu_raw.c0TxAlmFull),

              .first(c0_fifo_first),
              .deq_en(c0_fifo_deq),
              .notEmpty(c0_fifo_notEmpty)
              );


    // ====================================================================
    //
    // Channel 1 Tx buffer.
    //
    //   Same principle as channel 0 above.
    //
    // ====================================================================

    localparam C1TX_BITS = $bits(t_if_cci_mpf_c1_Tx);

    // Request payload exists when one of the valid bits is set.
    logic c1_enq_en;
    assign c1_enq_en = cci_mpf_c1TxIsValid(afu_raw.c1Tx);

    logic c1_notEmpty;

    // Pull request details out of the head of the FIFO.
    t_if_cci_mpf_c1_Tx c1_first;

    // Forward the FIFO to the buffered output.  The valid bits are
    // only meaningful when the FIFO isn't empty.
    assign afu_buf.c1Tx = cci_mpf_c1TxMaskValids(c1_first, c1_notEmpty);

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(C1TX_BITS),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      c1_fifo(.clk,
              .reset_n(afu_buf.reset_n),

              // The concatenated field order must match the use of c1_first above.
              .enq_data(afu_raw.c1Tx),
              .enq_en(c1_enq_en),
              .notFull(),
              .almostFull(afu_raw.c1TxAlmFull),

              .first(c1_first),
              .deq_en(deqC1Tx),
              .notEmpty(c1_notEmpty)
              );
endmodule // cci_mpf_shim_buffer_afu