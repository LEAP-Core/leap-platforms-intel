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

    cci_bus_t                      cci_bus            // CCI bus interface
   );

   assign cci_bus.rx0.header     = rx_c0_header;
   assign cci_bus.rx0.data       = rx_c0_data;
   assign cci_bus.rx0.wrvalid    = rx_c0_wrvalid;
   assign cci_bus.rx0.rdvalid    = rx_c0_rdvalid;
   assign cci_bus.rx0.cfgvalid   = rx_c0_cfgvalid;

   // Perhaps the read metadata decode should be a different module
   assign cci_bus.rx0.read_metadata.is_read   = cci_bus.rx0.header[12];   
   assign cci_bus.rx0.read_metadata.is_header = cci_bus.rx0.header[11];   
   assign cci_bus.rx0.read_metadata.rob_addr  = cci_bus.rx0.header[10:0];   
   
   assign cci_bus.rx1.header     = rx_c1_header;
   assign cci_bus.rx1.wrvalid    = rx_c1_wrvalid;

   assign tx_c0_header           = cci_bus.tx0.header;
   assign tx_c0_rdvalid          = cci_bus.tx0.rdvalid;
   assign cci_bus.tx0.almostfull = tx_c0_almostfull;

   assign tx_c1_header           = cci_bus.tx1.header;
   assign tx_c1_data             = cci_bus.tx1.data;
   assign tx_c1_wrvalid          = cci_bus.tx1.wrvalid;
   assign cci_bus.tx1.almostfull = tx_c1_almostfull;

   assign cci_bus.lp_initdone    = lp_initdone;

endmodule // cci_adaptor
