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

module qpi_wrapper#(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512)
(
    // ---------------------------global signals-------------------------------------------------
    clk,                 //              in    std_logic;  -- Core clock
    resetb,              //              in    std_logic;  -- Use SPARINGLY only for control
    // ---------------------------IF signals between SPL and FPL  --------------------------------
    rx_c0_header,        // [RXHDR_WIDTH-1:0]   cci_intf:           Rx header to SPL channel 0
    rx_c0_data,          // [CACHE_WIDTH-1:0]   cci_intf:           data response to SPL | no back pressure
    rx_c0_wrvalid,       //                     cci_intf:           write response enable
    rx_c0_rdvalid,       //                     cci_intf:           read response enable
    rx_c0_cfgvalid,      //                     cci_intf:           config response enable
    rx_c1_header,        // [RXHDR_WIDTH-1:0]   cci_intf:           Rx header to SPL channel 1
    rx_c1_wrvalid,       //                     cci_intf:           write response valid

    tx_c0_header,        // [TXHDR_WIDTH-1:0]   cci_intf:           Tx Header from SPL channel 0
    tx_c0_rdvalid,       //                     cci_intf:           Tx read request enable
    tx_c1_header,        //                     cci_intf:           Tx Header from SPL channel 1
    tx_c1_data,          //                     cci_intf:           Tx data from SPL
    tx_c1_wrvalid,       //                     cci_intf:           Tx write request enable
    tx_c0_almostfull,    //                     cci_intf:           Tx memory channel 0 almost full
    tx_c1_almostfull,    //                     cci_intf:           TX memory channel 1 almost full

    lp_initdone          // Link initialization is complete
);


   output                     clk;                // Core clock
   output                     resetb;             // Use SPARINGLY only for control

   output [RXHDR_WIDTH-1:0]   rx_c0_header;       // Rx header to SPL channel 0
   output [CACHE_WIDTH-1:0]   rx_c0_data;         // data response to SPL | no back pressure
   output                     rx_c0_wrvalid;      // write response enable
   output                     rx_c0_rdvalid;      // read response enable
   output                     rx_c0_cfgvalid;     // config response enable
   output [RXHDR_WIDTH-1:0]   rx_c1_header;       // Rx header to SPL channel 1
   output                     rx_c1_wrvalid;      // write response valid

   input [TXHDR_WIDTH-1:0]    tx_c0_header;       // Tx Header from SPL channel 0
   input                      tx_c0_rdvalid;      // Tx read request enable
   input [TXHDR_WIDTH-1:0]    tx_c1_header;       // Tx Header from SPL channel 1
   input [CACHE_WIDTH-1:0]    tx_c1_data;         // Tx data from SPL
   input                      tx_c1_wrvalid;      // Tx write request enable
   output                     tx_c0_almostfull;   // Tx memory channel 0 almost full
   output                     tx_c1_almostfull;   // TX memory channel 1 almost full

   output 		     lp_initdone;        // Link initialization is complete

   // Instantiate simulation controller.  The cci_mem_translator has
   // an empty interface, since it uses some kind of vpi-style
   // interdface for communications.
   
   cci_mem_translator translator();

   // Wire the external signals up as OOMRs.
   // Input
   assign clk = translator.afu_wrapper_inst.cafu_top_0.clk;          
   assign resetb = translator.afu_wrapper_inst.cafu_top_0.resetb;       

   assign rx_c0_header     = translator.afu_wrapper_inst.cafu_top_0.rx_c0_header; 
   assign rx_c0_data       = translator.afu_wrapper_inst.cafu_top_0.rx_c0_data;   
   assign rx_c0_wrvalid    = translator.afu_wrapper_inst.cafu_top_0.rx_c0_wrvalid;
   assign rx_c0_rdvalid    = translator.afu_wrapper_inst.cafu_top_0.rx_c0_rdvalid;
   assign rx_c0_cfgvalid   = translator.afu_wrapper_inst.cafu_top_0.rx_c0_cfgvalid;
   assign rx_c1_header     = translator.afu_wrapper_inst.cafu_top_0.rx_c1_header; 
   assign rx_c1_wrvalid    = translator.afu_wrapper_inst.cafu_top_0.rx_c1_wrvalid;
                             
   assign tx_c1_wrvalid    = translator.afu_wrapper_inst.cafu_top_0.tx_c1_wrvalid;
   assign tx_c0_almostfull = translator.afu_wrapper_inst.cafu_top_0.tx_c0_almostfull;   
   assign tx_c1_almostfull = translator.afu_wrapper_inst.cafu_top_0.tx_c1_almostfull;

   assign lp_initdone    = translator.afu_wrapper_inst.cafu_top_0.lp_initdone;  

   // Output
   assign translator.afu_wrapper_inst.cafu_top_0.tx_c0_header  = tx_c0_header; 
   assign translator.afu_wrapper_inst.cafu_top_0.tx_c0_rdvalid = tx_c0_rdvalid;
   assign translator.afu_wrapper_inst.cafu_top_0.tx_c1_header  = tx_c1_header; 
   assign translator.afu_wrapper_inst.cafu_top_0.tx_c1_data    =  tx_c1_data;   
                                             
endmodule
   
