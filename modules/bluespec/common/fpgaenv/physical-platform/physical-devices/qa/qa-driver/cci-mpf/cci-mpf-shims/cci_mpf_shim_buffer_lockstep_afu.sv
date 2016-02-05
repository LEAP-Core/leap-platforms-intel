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
// The same as cci_mpf_shim_buffer_afu except that channels 0 and 1 are held
// together and move through the buffer in lock step.  This is important
// for portions of the pipeline that need to maintain read/write ordering.
//

module cci_mpf_shim_buffer_lockstep_afu
  #(
    parameter N_ENTRIES = CCI_TX_ALMOST_FULL_THRESHOLD + 2,
    parameter THRESHOLD = CCI_TX_ALMOST_FULL_THRESHOLD
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

    // Dequeue signal combined with the buffering make the buffered interface
    // latency insensitive.  Requests sit in the buffers unless explicitly
    // removed.
    //
    // Unlike cci_mpf_shim_buffer_afu, a single deq signal moves both channels.
    // The client must be prepared to move both channels or none.
    input logic deqTx
    );

    assign afu_raw.reset = afu_buf.reset;

    //
    // Rx wires pass through toward the AFU.  They are latency sensitive
    // since the CCI provides no back pressure.
    //
    assign afu_raw.c0Rx = afu_buf.c0Rx;
    assign afu_raw.c1Rx = afu_buf.c1Rx;


    // ====================================================================
    //
    // Tx buffer.
    //
    //   The buffer triggers TxAlmFull when there are 4 or fewer slots
    //   available, as required by the CCI specification.  Unlike the
    //   usual CCI request interface, movement through the pipeline is
    //   explicit.  The code that instantiates this buffer must dequeue
    //   the head of the FIFO in order to consume a request.
    //
    // ====================================================================

    localparam C0TX_BITS = $bits(t_if_cci_mpf_c0_Tx);
    localparam C1TX_BITS = $bits(t_if_cci_mpf_c1_Tx);
    localparam TX_BITS = C0TX_BITS + C1TX_BITS;

    // Request payload exists when one of the valid bits is set.
    logic c0_enq_en;
    assign c0_enq_en = cci_mpf_c0TxIsValid(afu_raw.c0Tx);
    logic c1_enq_en;
    assign c1_enq_en = cci_mpf_c1TxIsValid(afu_raw.c1Tx);
    logic enq_en;
    assign enq_en = c0_enq_en || c1_enq_en;

    logic notEmpty;

    // Pull request details out of the head of the FIFO.
    logic [TX_BITS-1 : 0] first;
    always_comb
    begin
        { afu_buf.c0Tx, afu_buf.c1Tx } = first;

        // Valid bits are only meaningful when the FIFO isn't empty.
        afu_buf.c0Tx = cci_mpf_c0TxMaskValids(afu_buf.c0Tx, notEmpty);
        afu_buf.c1Tx = cci_mpf_c1TxMaskValids(afu_buf.c1Tx, notEmpty);
    end

    logic almostFull;
    assign afu_raw.c0TxAlmFull = almostFull;
    assign afu_raw.c1TxAlmFull = almostFull;


    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(TX_BITS),
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      c1_fifo(.clk,
              .reset(afu_buf.reset),

              // The concatenated field order must match the use of c1_first above.
              .enq_data({ afu_raw.c0Tx, afu_raw.c1Tx }),
              .enq_en,
              .notFull(),
              .almostFull,

              .first,
              .deq_en(deqTx),
              .notEmpty(notEmpty)
              );


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) is unbuffered.
    //
    // ====================================================================

    assign afu_buf.c2Tx = afu_raw.c2Tx;

endmodule // cci_mpf_shim_buffer_lockstep_afu

