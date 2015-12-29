//
// MPF's view of CCI expressed as a SystemVerilog interface.
//

`ifndef CCI_MPF_IF_VH
`define CCI_MPF_IF_VH

import cci_mpf_if_pkg::*;

interface cci_mpf_if
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
    logic                        reset_n;

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
       input  reset_n,

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
       output reset_n,

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
       input  reset_n,

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

`endif //  CCI_MPF_IF_VH
