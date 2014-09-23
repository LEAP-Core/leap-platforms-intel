//====================================================================
//
// cci_adaptor.sv
//
// Original Author : George Powley
// Original Date   : 2014/08/15
//
// Copyright (c) 2014 Intel Corporation
// Intel Proprietary
//
// Description:
// - Convert CCI pins to cci_bus interface
//
//====================================================================

`include "qpi.vh"

module cci_adaptor
  #(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512)
  (
    input logic [RXHDR_WIDTH-1:0]  rx_c0_header,      // Rx header to SPL channel 0
    input logic [CACHE_WIDTH-1:0]  rx_c0_data,        // data response to SPL | no back pressure
    input logic                    rx_c0_wrvalid,     // write response enable
    input logic                    rx_c0_rdvalid,     // read response enable
    input logic                    rx_c0_cfgvalid,    // config response enable
    input logic [RXHDR_WIDTH-1:0]  rx_c1_header,      // Rx header to SPL channel 1
    input logic                    rx_c1_wrvalid,     // write response valid
   
    output logic [TXHDR_WIDTH-1:0] tx_c0_header,      // Tx Header from SPL channel 0
    output logic                   tx_c0_rdvalid,     // Tx read request enable
    output logic [TXHDR_WIDTH-1:0] tx_c1_header,      // Tx Header from SPL channel 1
    output logic [CACHE_WIDTH-1:0] tx_c1_data,        // Tx data from SPL
    output logic                   tx_c1_wrvalid,     // Tx write request enable
    input logic                    tx_c0_almostfull,  // Tx memory channel 0 almost full
    input logic                    tx_c1_almostfull,  // TX memory channel 1 almost full
   
    input logic                    lp_initdone,       // Link initialization is complete

    input  tx_c0_t                 tx0,
    input  tx_c1_t                 tx1,
    output rx_c0_t                 rx0,
    output rx_c1_t                 rx1,
    output logic                   tx0_almostfull,
    output logic                   tx1_almostfull         

   );

   assign rx0.header     = rx_c0_header;
   assign rx0.data       = rx_c0_data;
   assign rx0.wrvalid    = rx_c0_wrvalid;
   assign rx0.rdvalid    = rx_c0_rdvalid;
   assign rx0.cfgvalid   = rx_c0_cfgvalid;

   assign rx1.header     = rx_c1_header;
   assign rx1.wrvalid    = rx_c1_wrvalid;

   assign tx_c0_header           = tx0.header;
   assign tx_c0_rdvalid          = tx0.rdvalid;
   assign tx0_almostfull         = tx_c0_almostfull;

   assign tx_c1_header           = tx1.header;
   assign tx_c1_data             = tx1.data;
   assign tx_c1_wrvalid          = tx1.wrvalid;
   assign tx1_almostfull         = tx_c1_almostfull;

      
endmodule // cci_adaptor
