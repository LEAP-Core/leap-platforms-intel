// ***************************************************************************
//                               INTEL CONFIDENTIAL
//
//        Copyright (C) 2008-2011 Intel Corporation All Rights Reserved.
//
// The source code contained or described herein and all  documents related to
// the  source  code  ("Material")  are  owned  by  Intel  Corporation  or its
// suppliers  or  licensors.    Title  to  the  Material  remains  with  Intel
// Corporation or  its suppliers  and licensors.  The Material  contains trade
// secrets  and  proprietary  and  confidential  information  of  Intel or its
// suppliers and licensors.  The Material is protected  by worldwide copyright
// and trade secret laws and treaty provisions. No part of the Material may be
// used,   copied,   reproduced,   modified,   published,   uploaded,  posted,
// transmitted,  distributed,  or  disclosed  in any way without Intel's prior
// express written permission.
//
// No license under any patent,  copyright, trade secret or other intellectual
// property  right  is  granted  to  or  conferred  upon  you by disclosure or
// delivery  of  the  Materials, either expressly, by implication, inducement,
// estoppel or otherwise.  Any license under such intellectual property rights
// must be express and approved by Intel in writing.
//
// Module Name:         cafu_top.v
// Author:              Rahul R Sharma <rahul.r.sharma@intel.com>
//
// Description:         This module instantiates the NLB and standardizes
//                      port names for cci_mem_translator
//                      This mapping file has to be changed when AFU
//                      port names change from default names.
//
// Instructions:        This file is modified to attach ASE HW ports to the AFU
//
// ***************************************************************************

module cafu_top #(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512)
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


   /*
    * DO NOT MODIFY ABOVE THIS COMMENT 
    */

   // since we use OOMRs, this code is completely empty.

   /*
    * DO NOT MODIFY BELOW THIS COMMENT
    */
   
   
endmodule

