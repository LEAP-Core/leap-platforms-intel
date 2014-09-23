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

`include "qpi.vh"

module qpi_driver#(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512, UMF_WIDTH=128)
(
    // ---------------------------global signals-------------------------------------------------
    clk,                 //              in    std_logic;  -- Core clock
    resetb,              //              in    std_logic;  -- Use SPARINGLY only for control

    // --------------------------- QPI Facing Interface           --------------------------------
    // --------------------------- IF signals between SPL and FPL --------------------------------
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

    lp_initdone,         // Link initialization is complete


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

   // QPI facing interface
   
   input                     clk;                // Core clock
   input                     resetb;             // Use SPARINGLY only for control

   input [RXHDR_WIDTH-1:0]   rx_c0_header;       // Rx header to SPL channel 0
   input [CACHE_WIDTH-1:0]   rx_c0_data;         // data response to SPL | no back pressure
   input                     rx_c0_wrvalid;      // write response enable
   input                     rx_c0_rdvalid;      // read response enable
   input                     rx_c0_cfgvalid;     // config response enable
   input [RXHDR_WIDTH-1:0]   rx_c1_header;       // Rx header to SPL channel 1
   input                     rx_c1_wrvalid;      // write response valid

   output [TXHDR_WIDTH-1:0]  tx_c0_header;       // Tx Header from SPL channel 0
   output                    tx_c0_rdvalid;      // Tx read request enable
   output [TXHDR_WIDTH-1:0]  tx_c1_header;       // Tx Header from SPL channel 1
   output [CACHE_WIDTH-1:0]  tx_c1_data;         // Tx data from SPL
   output                    tx_c1_wrvalid;      // Tx write request enable
   input                     tx_c0_almostfull;   // Tx memory channel 0 almost full
   input                     tx_c1_almostfull;   // TX memory channel 1 almost full

   input 		     lp_initdone;        // Link initialization is complete

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

   // Internal module wiring.

   afu_csr_t              csr;
 
   frame_arb_t            frame_writer;
   frame_arb_t            frame_reader;
   frame_arb_t            status_writer;
   channel_grant_arb_t    write_grant;
   channel_grant_arb_t    read_grant;
   
   tx_c0_t                tx0;
   tx_c1_t                tx1;
   rx_c0_t                rx0;
   rx_c1_t                rx1;
   logic                  tx0_almostfull;
   logic                  tx1_almostfull;
              
   // connect CCI pins to cci_bus
   cci_adaptor       cci_adaptor_inst(.*);
   
   qpi_csr           qpi_csr_inst(.*);

   frame_reader      frame_reader_inst(.*);
   frame_writer      frame_writer_inst(.*);
   status_writer     status_writer_inst(.*);
   cci_write_arbiter write_arb(.*);
   cci_read_arbiter  read_arb(.*);
  
endmodule
   
