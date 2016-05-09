// ***************************************************************************
//
//        Copyright (C) 2008-2014 Intel Corporation All Rights Reserved.
//
//
// Engineer:            Arthur.Sheiman@Intel.com
// Create Date:         02-17-10 02:28
// Edited by:           Pratik.m.marolia@intel.com
// Edit Date:           10/09/2014
// Module Name:         cci_std_afu
// Project:             QLP2 with CCI-S interface
// Description:         This module presents the CCI STANDARD port interface. Instantiate
//                      the user AFU in this module. For more information on CCI interface
//                      refer to "CCI Specification.pdf"
//
// ***************************************************************************
// CAUTION: sharath.jayaprakash@intel.com
// Interrupts and Umsgs are NOT supported as a part of system release 3.3. We 
// do expect to support these features in the future. These ports are 
// currently defined as placeholders. 
// When writing a wrapper for your AFU you need to define these ports for 
// compilation purposes.
// ***************************************************************************

`include "cci_mpf_platform.vh"

`ifdef MPF_HOST_IFC_CCIS

module cci_std_afu
    (// Link/Protocol (LP) clocks and reset
     input  /*var*/  logic             vl_clk_LPdomain_32ui,                      // CCI Inteface Clock. 32ui link/protocol clock domain.
     input  /*var*/  logic             vl_clk_LPdomain_16ui,                      // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_SystemReset_n,         // System Reset
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_SoftReset_n,           // CCI-S soft reset

     // Native CCI Interface (cache line interface for back end)
     /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
     input  /*var*/  logic      [17:0] ffs_vl18_LP32ui_lp2sy_C0RxHdr,             // System to LP header
     input  /*var*/  logic     [511:0] ffs_vl512_LP32ui_lp2sy_C0RxData,           // System to LP data 
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0RxWrValid,           // RxWrHdr valid signal 
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0RxRdValid,           // RxRdHdr valid signal
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0RxCgValid,           // RxCgHdr valid signal
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0RxUgValid,           // Rx Umsg Valid signal
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0RxIrValid,           // Rx Interrupt valid signal
     /* Channel 1 reserved for WRITE RESPONSE ONLY */
     input  /*var*/  logic      [17:0] ffs_vl18_LP32ui_lp2sy_C1RxHdr,             // System to LP header (Channel 1)
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C1RxWrValid,           // RxData valid signal (Channel 1)
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C1RxIrValid,           // Rx Interrupt valid signal (Channel 1)

     /*Channel 0 reserved for READ REQUESTS ONLY */        
     output /*var*/  logic      [60:0] ffs_vl61_LP32ui_sy2lp_C0TxHdr,             // System to LP header 
     output /*var*/  logic             ffs_vl_LP32ui_sy2lp_C0TxRdValid,           // TxRdHdr valid signals 
     /*Channel 1 reserved for WRITE REQUESTS ONLY */       
     output /*var*/  logic      [60:0] ffs_vl61_LP32ui_sy2lp_C1TxHdr,             // System to LP header
     output /*var*/  logic     [511:0] ffs_vl512_LP32ui_sy2lp_C1TxData,           // System to LP data 
     output /*var*/  logic             ffs_vl_LP32ui_sy2lp_C1TxWrValid,           // TxWrHdr valid signal
     output /*var*/  logic             ffs_vl_LP32ui_sy2lp_C1TxIrValid,           // Tx Interrupt valid signal
     /* Tx push flow control */
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C0TxAlmFull,           // Channel 0 almost full
     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_C1TxAlmFull,           // Channel 1 almost full

     input  /*var*/  logic             ffs_vl_LP32ui_lp2sy_InitDnForSys           // System layer is aok to run
     );

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
   
endmodule

`endif
