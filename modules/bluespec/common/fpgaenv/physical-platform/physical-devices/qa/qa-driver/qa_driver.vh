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

`ifndef QA_DRIVER_TYPES_VH
`define QA_DRIVER_TYPES_VH

//
// Widths of standard CCI interfaces
//

`define CCI_S_RX_HDR_WIDTH 18
`define CCI_S_TX_HDR_WIDTH 61

`define CCI_E_RX_HDR_WIDTH 24
`define CCI_E_TX_HDR_WIDTH 99


// Included because VCS fails to detect packages correctly.
`include "qa_driver_types.sv"


import qa_driver_types::*;
import qa_driver_csr_types::*;


//
// QA driver shims are composable because they conform to the same basic
// interface.  The interface holds all the connections between the
// platform (QLP) and the user code (AFU).  Most shims expose two copies
// of the interface: one connecting in the direction of the QLP and the
// other connecting in the direction of the QFU.
//
interface qlp_interface
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 14
    )
   (
    input logic clk
    );

    // Reset flows from QLP to AFU
    logic                        resetb;

    // Requests to QLP.  All objects are outputs flowing toward QLP except
    // the almost full ports, which provide flow control.
    logic [CCI_TX_HDR_WIDTH-1:0] C0TxHdr;
    logic                        C0TxRdValid;
    logic                        C0TxAlmFull;

    logic [CCI_TX_HDR_WIDTH-1:0] C1TxHdr;
    logic [CCI_DATA_WIDTH-1:0]   C1TxData;
    logic                        C1TxWrValid;
    logic                        C1TxIrValid;
    logic                        C1TxAlmFull;

    // Responses from QLP.  All objects are inputs from the QLP and flow
    // toward the AFU.  There is no flow control.  The AFU must be prepared
    // to receive responses for all in-flight requests.
    logic [CCI_RX_HDR_WIDTH-1:0] C0RxHdr;
    logic [CCI_DATA_WIDTH-1:0]   C0RxData;
    logic                        C0RxWrValid;
    logic                        C0RxRdValid;
    logic                        C0RxCgValid;
    logic                        C0RxUgValid;
    logic                        C0RxIrValid;

    logic [CCI_RX_HDR_WIDTH-1:0] C1RxHdr;
    logic                        C1RxWrValid;
    logic                        C1RxIrValid;

    // Port directions for connections in the direction of the QLP (platform)
    modport to_qlp
      (
       input  resetb,

       output C0TxHdr,
       output C0TxRdValid,
       input  C0TxAlmFull,

       output C1TxHdr,
       output C1TxData,
       output C1TxWrValid,
       output C1TxIrValid,
       input  C1TxAlmFull,

       input  C0RxHdr,
       input  C0RxData,
       input  C0RxWrValid,
       input  C0RxRdValid,
       input  C0RxCgValid,
       input  C0RxUgValid,
       input  C0RxIrValid,

       input  C1RxHdr,
       input  C1RxWrValid,
       input  C1RxIrValid
       );

    // Port directions for connections in the direction of the AFU (user code)
    modport to_afu
      (
       output resetb,

       input  C0TxHdr,
       input  C0TxRdValid,
       output C0TxAlmFull,

       input  C1TxHdr,
       input  C1TxData,
       input  C1TxWrValid,
       input  C1TxIrValid,
       output C1TxAlmFull,

       output C0RxHdr,
       output C0RxData,
       output C0RxWrValid,
       output C0RxRdValid,
       output C0RxCgValid,
       output C0RxUgValid,
       output C0RxIrValid,

       output C1RxHdr,
       output C1RxWrValid,
       output C1RxIrValid
       );


    // ====================================================================
    //
    // Snoop equivalents of the above interfaces: all the inputs and none
    // of the outputs.
    //
    // ====================================================================

    modport to_qlp_snoop
      (
       input  resetb,

       input  C0TxAlmFull,
       input  C1TxAlmFull,

       input  C0RxHdr,
       input  C0RxData,
       input  C0RxWrValid,
       input  C0RxRdValid,
       input  C0RxCgValid,
       input  C0RxUgValid,
       input  C0RxIrValid,

       input  C1RxHdr,
       input  C1RxWrValid,
       input  C1RxIrValid
       );

    modport to_afu_snoop
      (
       input  C0TxHdr,
       input  C0TxRdValid,

       input  C1TxHdr,
       input  C1TxData,
       input  C1TxWrValid,
       input  C1TxIrValid
       );

endinterface

`endif //  `ifndef QA_DRIVER_TYPES_VH
