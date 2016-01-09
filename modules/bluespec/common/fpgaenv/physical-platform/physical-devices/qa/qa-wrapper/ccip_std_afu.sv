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

import ccip_if_pkg::*;

module ccip_std_afu
   (
    // CCI-P Clocks and Resets
    input  logic        vl_clk_LPdomain_16ui,       // CCI interface clock
    input  logic        vl_clk_LPdomain_64ui,       // 1/4x Frequency of interface clock. Synchronous.
    input  logic        vl_clk_LPdomain_32ui,       // 1/2x Frequency of interface clock. Synchronous.
    input  logic        ffs_LP16ui_afu_SoftReset_n, // CCI-P Soft Reset
    input  logic [1:0]  ffs_LP16ui_afu_PwrState,    // CCI-P AFU Power State
    input  logic        ffs_LP16ui_afu_Error,       // CCI-P Protocol Error Detected

    // Data ports
    output t_if_ccip_Tx ffs_LP16ui_sTxData_afu,     // CCI-P Tx Port
    input  t_if_ccip_Rx ffs_LP16ui_sRxData_afu      // CCI-P Rx Port
    );

`ifdef USE_PLATFORM_CCIP

    // Instantiate LEAP top level.
    mk_model_Wrapper model_wrapper(
        .*,

        // Unconnected wires exposed by Bluespec that we can't turn off...
        .CLK(1'b0),
        .RST_N(1'b1),
        .CLK_qaDevClock(),
        .CLK_GATE_qaDevClock(),
        .RDY_clock_wire(),
        .RDY_reset_n_wire(),
        .EN_inputWires(1'b1),
        .RDY_inputWires());

`endif

endmodule // ccip_std_afu
