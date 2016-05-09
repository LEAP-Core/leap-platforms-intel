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



//
// This is the top level of the Intel QuickAssist simulation for LEAP.
// Bluespec expects the top level simulation build to have only CLK and RST_N.
// This module instantiates the simulation environment, which instantiates
// the user code through the usual QuickAssist cci_stf_afu() module.
//

`timescale 1ns/1ns

import "DPI-C" function string getenv(input string env_name);

`include "cci_mpf_platform.vh"

`ifdef MPF_HOST_IFC_CCIP
import ccip_if_pkg::*;
`endif

module qa_sim_top_level(CLK,
                        RST_N);
    input CLK;
    input RST_N;

`ifdef MPF_HOST_IFC_CCIS
    //
    // ASE for the original Xeon+FPGA SDP.  The emulator instantiates the
    // top level module, named cci_std_afu.
    //
    cci_emulator emulator();
`endif

`ifdef MPF_HOST_IFC_CCIP
    //
    // CCI-P emulation.  The emulator exports wires, which we pass to
    // the design's top level.
    //
    logic pClk;
    logic pClkDiv2;
    logic pClkDiv4;
    logic uClk_usr;
    logic uClk_usrDiv2;

    logic       pck_cp2af_softReset;
    logic [1:0] pck_cp2af_pwrState;   // CCI-P AFU Power State
    logic       pck_cp2af_error;      // CCI-P Protocol Error Detected
   
    t_if_ccip_Tx pck_af2cp_sTx;
    t_if_ccip_Rx pck_cp2af_sRx;
   
    // CCI-P emulator
    ccip_emulator ccip_emulator
       (
        .pClk,
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .pck_cp2af_softReset,
        .pck_cp2af_pwrState,
        .pck_cp2af_error,
        .pck_cp2af_sRx,
        .pck_af2cp_sTx
        );


    // CCIP AFU
    ccip_std_afu ccip_std_afu
       (
        .pClk,
        .pClkDiv2,
        .pClkDiv4,
        .uClk_usr,
        .uClk_usrDiv2,
        .pck_cp2af_softReset,
        .pck_cp2af_pwrState,
        .pck_cp2af_error,
        .pck_cp2af_sRx,
        .pck_af2cp_sTx
        );
`endif

    initial
    begin
        $dumpfile("driver_dump.vcd");
        if ({getenv("VCD_ENABLE_DUMP")} != "")
        begin
            $display("Enabling dump to driver_dump.vcd");
            $dumpvars(0, qa_sim_top_level);
            $dumpon;
        end
        else
        begin
            $display("VCD disabled. To enable: \"setenv VCD_ENABLE_DUMP 1\".");
            $system("rm -f driver_dump.vcd");
        end
    end
endmodule // qa_sim_top_level
