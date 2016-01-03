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
// This is more a primitive shim than a full fledged shim.  It takes a
// FIU-side raw connection (wires) and adds one cycle of buffering to
// all the RX signals that flow toward the AFU.  The TX signals flowing
// toward the FIU pass through as wires.
//
// This structure is useful when a shim needs to look up some data
// associated with a response that is stored in block RAM.  The RAM read
// request can be triggered when the response arrives from the FIU and
// the RAM response is then available when the response exits the
// buffer built here.
//
// Unlike the equivalent AFU buffer there is no flow control.  The CCI
// interface does not provide for back pressure on the flow of responses.
//

module cci_mpf_shim_buffer_fiu
  #(
    // Register outbound signals if nonzero.
    parameter REGISTER_OUTBOUND = 0
    )
   (
    input  logic clk,

    // Raw unbuffered connection.  This is the FIU-side connection of the
    // parent module.
    cci_mpf_if.to_fiu fiu_raw,

    // Generated buffered connection.  The confusing interface direction
    // arises because the shim is an interposer on the FIU side of a
    // standard shim.
    cci_mpf_if.to_afu fiu_buf
    );

    assign fiu_buf.reset_n = fiu_raw.reset_n;

    //
    // Tx wires pass through toward the FIU. They are straight assignments
    // if REGISTER_OUTBOUND is 0.
    //
    generate
        if (REGISTER_OUTBOUND == 0)
        begin
            always_comb
            begin
                fiu_raw.c0Tx = fiu_buf.c0Tx;
                fiu_buf.c0TxAlmFull = fiu_raw.c0TxAlmFull;

                fiu_raw.c1Tx = fiu_buf.c1Tx;
                fiu_buf.c1TxAlmFull = fiu_raw.c1TxAlmFull;
            end
        end
        else
        begin
            always_ff @(posedge clk)
            begin
                fiu_raw.c0Tx <= fiu_buf.c0Tx;
                fiu_buf.c0TxAlmFull <= fiu_raw.c0TxAlmFull;

                fiu_raw.c1Tx <= fiu_buf.c1Tx;
                fiu_buf.c1TxAlmFull <= fiu_raw.c1TxAlmFull;
            end
        end
    endgenerate

    //
    // Rx input is registered for a one cycle delay.
    //
    always_ff @(posedge clk)
    begin
        fiu_buf.c0Rx <= fiu_raw.c0Rx;
        fiu_buf.c1Rx <= fiu_raw.c1Rx;
    end

endmodule // cci_mpf_shim_buffer_fiu

