//
// Copyright (c) 2014, Intel Corporation
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

// This module wraps the QuickAssist cache coherence interface in
// verilog.  Since we subordinate the CCI interface as a device
// driver, we use verilog OOMRs to bypass the interface.

module qpi_wrapper#(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512, UMF_WIDTH=128)
(
    // ---------------------------global signals-------------------------------------------------
    clk,                 //              in    std_logic;  -- Core clock
    resetb,              //              in    std_logic;  -- Use SPARINGLY only for control

    // --------------------------- LEAP Facing Interface           --------------------------------
    // RX side
    rx_data,
    rx_not_empty,
    rx_rdy,
    rx_enable,

    // TX side
    tx_data,
    tx_not_full,
    tx_rdy,
    tx_enable

);


   output                     clk;                // Core clock
   output                     resetb;             // Use SPARINGLY only for control

   // LEAP facing interface
   output [UMF_WIDTH-1:0]    rx_data;   
   output                    rx_not_empty;
   output                    rx_rdy;
   input                     rx_enable;
   
   // TX side
   input [UMF_WIDTH-1:0]     tx_data;
   output                    tx_not_full;
   output                    tx_rdy;
   input                     tx_enable;
   
   // Instantiate simulation controller.  The cci_mem_translator has
   // an empty interface, since it uses some kind of vpi-style
   // interdface for communications.
   
   cci_emulator emulator();

   // Wire the external signals to driver as OOMRs.

   assign clk = emulator.cci_std_afu.vl_clk_LPdomain_32ui;
   assign resetb = emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_SoftReset_n;
   
   qpi_driver driver(
        .clk(emulator.cci_std_afu.vl_clk_LPdomain_32ui),
        .resetb(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_SoftReset_n),

        .rx_c0_header(emulator.cci_std_afu.ffs_vl18_LP32ui_lp2sy_C0RxHdr),
        .rx_c0_data(emulator.cci_std_afu.ffs_vl512_LP32ui_lp2sy_C0RxData),
        .rx_c0_wrvalid(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C0RxWrValid),
        .rx_c0_rdvalid(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C0RxRdValid),
        .rx_c0_cfgvalid(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C0RxCgValid),
        //    rb2cf_C0RxUMsgValid
        //    rb2cf_C0RxIntrValid
        .rx_c1_header(emulator.cci_std_afu.ffs_vl18_LP32ui_lp2sy_C1RxHdr),
        .rx_c1_wrvalid(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C1RxWrValid),
        //    rb2cf_C1RxIntrValid

        .tx_c0_header(emulator.cci_std_afu.ffs_vl61_LP32ui_sy2lp_C0TxHdr),
        .tx_c0_rdvalid(emulator.cci_std_afu.ffs_vl_LP32ui_sy2lp_C0TxRdValid),
        .tx_c1_header(emulator.cci_std_afu.ffs_vl61_LP32ui_sy2lp_C1TxHdr),
        .tx_c1_data(emulator.cci_std_afu.ffs_vl512_LP32ui_sy2lp_C1TxData),
        .tx_c1_wrvalid(emulator.cci_std_afu.ffs_vl_LP32ui_sy2lp_C1TxWrValid),
        //    cf2ci_C1TxIntrValid
        .tx_c0_almostfull(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C0TxAlmFull),
        .tx_c1_almostfull(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_C1TxAlmFull),

        .lp_initdone(emulator.cci_std_afu.ffs_vl_LP32ui_lp2sy_InitDnForSys),

        .rx_data(rx_data),
        .rx_not_empty(rx_not_empty),
        .rx_rdy(rx_rdy),
        .rx_enable(rx_enable),

        // TX side
        .tx_data(tx_data),
        .tx_not_full(tx_not_full),
        .tx_rdy(tx_rdy),
        .tx_enable(tx_enable)
    );

   initial
     begin

        $dumpfile("driver_dump.vcd");
        $dumpvars(0, driver);
        $dumpon;

     end

endmodule

