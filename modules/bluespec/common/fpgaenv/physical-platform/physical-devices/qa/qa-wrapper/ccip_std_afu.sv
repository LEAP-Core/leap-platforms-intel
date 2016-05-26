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

`include "cci_mpf_platform.vh"

`ifdef MPF_HOST_IFC_CCIP

`include "awb/provides/clocks_device_params.bsh"

import ccip_if_pkg::*;

module ccip_std_afu
   (
    // CCI-P Clocks and Resets
    input           logic             pClk,              // 400MHz - CCI-P clock domain. Primary interface clock
    input           logic             pClkDiv2,          // 200MHz - CCI-P clock domain.
    input           logic             pClkDiv4,          // 100MHz - CCI-P clock domain.
    input           logic             uClk_usr,          // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
    input           logic             uClk_usrDiv2,      // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
    input           logic             pck_cp2af_softReset,      // CCI-P ACTIVE HIGH Soft Reset
    input           logic [1:0]       pck_cp2af_pwrState,       // CCI-P AFU Power State
    input           logic             pck_cp2af_error,          // CCI-P Protocol Error Detected

    // Interface structures
    input           t_if_ccip_Rx      pck_cp2af_sRx,        // CCI-P Rx Port
    output          t_if_ccip_Tx      pck_af2cp_sTx         // CCI-P Tx Port
    );

    //
    // Quartus doesn't permit creating a new clock Inside the CCI-P partial
    // reconfiguration region.  The user must currently pick one of the
    // incoming clocks.
    //
    // In the future uClk_usr will be programmable.
    //
    logic user_clk;

    localparam MODEL_CLOCK_FREQ = `MODEL_CLOCK_FREQ;

    generate
        if (MODEL_CLOCK_FREQ == 400)
            assign user_clk = pClk;
        else if (MODEL_CLOCK_FREQ == 300)
            assign user_clk = uClk_usr;
        else if (MODEL_CLOCK_FREQ == 200)
            assign user_clk = pClkDiv2;
        else if (MODEL_CLOCK_FREQ == 150)
            assign user_clk = uClk_usrDiv2;
        else if (MODEL_CLOCK_FREQ == 100)
            assign user_clk = pClkDiv4;
        else
            $fatal("Unsupported user clock frequency: %d", MODEL_CLOCK_FREQ);
    endgenerate


    //
    // Reset synchronizer
    //
    (* preserve *) logic user_rst_T1;
    (* preserve *) logic user_rst_T2;
    logic user_rst;

    always @(posedge user_clk)
    begin
        user_rst_T1 <= pck_cp2af_softReset;
        user_rst_T2 <= user_rst_T1;
        user_rst    <= user_rst_T2;
    end


    // Instantiate LEAP top level.
    mk_model_Wrapper
      model_wrapper
       (
        // Edge interface clock and reset
        .pClk,
        .pck_cp2af_softReset,

        // Clocks to be used by user logic
        .USER_CLK(user_clk),
        .USER_RST(user_rst),

        .*,

        // Unconnected wires exposed by Bluespec that we can't turn off...
        .CLK(1'b0),
        .RST_N(1'b1),
        .CLK_qaDevClock(),
        .CLK_GATE_qaDevClock(),
        .RDY_plat_ifc_clock_wire(),
        .RDY_plat_ifc_reset_wire(),
        .RDY_user_clock_wire(),
        .RDY_user_reset_wire(),
        .EN_inputWires(1'b1),
        .RDY_inputWires());

endmodule // ccip_std_afu

`endif
