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

module qa_driver
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 14,
    parameter UMF_WIDTH=128
    )
   (
    input logic vl_clk_LPdomain_32ui,                      // CCI Inteface Clock. 32ui link/protocol clock domain.
    input logic ffs_vl_LP32ui_lp2sy_SoftReset_n,           // CCI-S soft reset

    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    //
    // To client FIFO
    //
    output logic [UMF_WIDTH-1:0] rx_fifo_data,   
    output logic                 rx_fifo_rdy,
    input  logic                 rx_fifo_enable,
   
    //
    // From client FIFO
    //
    input  logic [UMF_WIDTH-1:0] tx_fifo_data,
    output logic                 tx_fifo_rdy,
    input  logic                 tx_fifo_enable,

    //
    // Client status registers.  Mostly useful for debugging.
    //
    // Only one status register read will be in flight at once.
    // The FPGA-side client must respond to a request with exactly
    // one response.  No specific timing is required.
    //
    // Clients are not required to implement this as long as the host
    // ReadStatusReg() method is never called.  In this case just
    // tie off sreg_rsp_enable.
    //
    output [31:0]                sreg_req_addr,
    output logic                 sreg_req_rdy,
    input  [63:0]                sreg_rsp,
    input  logic                 sreg_rsp_enable,

    // -------------------------------------------------------------------
    //
    //   System interface.  These signals come directly from the CCI.
    //
    // -------------------------------------------------------------------

    input  logic                   vl_clk_LPdomain_16ui,                // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
    input  logic                   ffs_vl_LP32ui_lp2sy_SystemReset_n,   // System Reset

    // Native CCI Interface (cache line interface for back end)
    /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
    input  logic [CCI_RX_HDR_WIDTH-1:0] ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
    input  logic [CCI_DATA_WIDTH-1:0] ffs_vl512_LP32ui_lp2sy_C0RxData, // System to LP data 
    input  logic                   ffs_vl_LP32ui_lp2sy_C0RxWrValid,     // RxWrHdr valid signal 
    input  logic                   ffs_vl_LP32ui_lp2sy_C0RxRdValid,     // RxRdHdr valid signal
    input  logic                   ffs_vl_LP32ui_lp2sy_C0RxCgValid,     // RxCgHdr valid signal
    input  logic                   ffs_vl_LP32ui_lp2sy_C0RxUgValid,     // Rx Umsg Valid signal
    input  logic                   ffs_vl_LP32ui_lp2sy_C0RxIrValid,     // Rx Interrupt valid signal
    /* Channel 1 reserved for WRITE RESPONSE ONLY */
    input  logic [CCI_RX_HDR_WIDTH-1:0] ffs_vl18_LP32ui_lp2sy_C1RxHdr,       // System to LP header (Channel 1)
    input  logic                   ffs_vl_LP32ui_lp2sy_C1RxWrValid,     // RxData valid signal (Channel 1)
    input  logic                   ffs_vl_LP32ui_lp2sy_C1RxIrValid,     // Rx Interrupt valid signal (Channel 1)

    /*Channel 0 reserved for READ REQUESTS ONLY */        
    output logic [CCI_TX_HDR_WIDTH-1:0] ffs_vl61_LP32ui_sy2lp_C0TxHdr,       // System to LP header 
    output logic                   ffs_vl_LP32ui_sy2lp_C0TxRdValid,     // TxRdHdr valid signals 
    /*Channel 1 reserved for WRITE REQUESTS ONLY */       
    output logic [CCI_TX_HDR_WIDTH-1:0] ffs_vl61_LP32ui_sy2lp_C1TxHdr,       // System to LP header
    output logic [CCI_DATA_WIDTH-1:0] ffs_vl512_LP32ui_sy2lp_C1TxData, // System to LP data 
    output logic                   ffs_vl_LP32ui_sy2lp_C1TxWrValid,     // TxWrHdr valid signal
    output logic                   ffs_vl_LP32ui_sy2lp_C1TxIrValid,     // Tx Interrupt valid signal
    /* Tx push flow control */
    input  logic                   ffs_vl_LP32ui_lp2sy_C0TxAlmFull,     // Channel 0 almost full
    input  logic                   ffs_vl_LP32ui_lp2sy_C1TxAlmFull,     // Channel 1 almost full

    input  logic                   ffs_vl_LP32ui_lp2sy_InitDnForSys     // System layer is aok to run
    );

    //
    // The driver uses structures and shorter names to group the CCI.
    // Map names here.
    //
    logic  clk;
    assign clk = vl_clk_LPdomain_32ui;

    logic  qlp_resetb;
    assign qlp_resetb = ffs_vl_LP32ui_lp2sy_SoftReset_n &&
                        ffs_vl_LP32ui_lp2sy_InitDnForSys;

    //
    // Buffer outgoing write requests for timing
    //
    logic [CCI_TX_HDR_WIDTH-1:0] qlp_C0TxHdr;
    logic                        qlp_C0TxRdValid;
    logic                        qlp_C0TxAlmFull;

    logic [CCI_TX_HDR_WIDTH-1:0] qlp_C1TxHdr;
    logic [CCI_DATA_WIDTH-1:0]   qlp_C1TxData;
    logic                        qlp_C1TxWrValid;
    logic                        qlp_C1TxIrValid;
    logic                        qlp_C1TxAlmFull;

    always_ff @(posedge clk)
    begin
        ffs_vl61_LP32ui_sy2lp_C0TxHdr <= qlp_C0TxHdr;
        ffs_vl_LP32ui_sy2lp_C0TxRdValid <= qlp_C0TxRdValid;
        qlp_C0TxAlmFull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

        ffs_vl61_LP32ui_sy2lp_C1TxHdr <= qlp_C1TxHdr;
        ffs_vl512_LP32ui_sy2lp_C1TxData <= qlp_C1TxData;
        ffs_vl_LP32ui_sy2lp_C1TxWrValid <= qlp_C1TxWrValid;
        ffs_vl_LP32ui_sy2lp_C1TxIrValid <= qlp_C1TxIrValid;
        qlp_C1TxAlmFull <= ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
    end


    //
    // Buffer incoming read responses for timing
    //
    logic [CCI_RX_HDR_WIDTH-1:0] qlp_C0RxHdr;
    logic [CCI_DATA_WIDTH-1:0]   qlp_C0RxData;
    logic                        qlp_C0RxWrValid;
    logic                        qlp_C0RxRdValid;
    logic                        qlp_C0RxCgValid;
    logic                        qlp_C0RxUgValid;
    logic                        qlp_C0RxIrValid;

    logic [CCI_RX_HDR_WIDTH-1:0] qlp_C1RxHdr;
    logic                        qlp_C1RxWrValid;
    logic                        qlp_C1RxIrValid;

    always_ff @(posedge clk)
    begin
        qlp_C0RxHdr     <= ffs_vl18_LP32ui_lp2sy_C0RxHdr;
        qlp_C0RxData    <= ffs_vl512_LP32ui_lp2sy_C0RxData;
        qlp_C0RxWrValid <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
        qlp_C0RxRdValid <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
        qlp_C0RxCgValid <= ffs_vl_LP32ui_lp2sy_C0RxCgValid;
        qlp_C0RxUgValid <= ffs_vl_LP32ui_lp2sy_C0RxUgValid;
        qlp_C0RxIrValid <= ffs_vl_LP32ui_lp2sy_C0RxIrValid;

        qlp_C1RxHdr     <= ffs_vl18_LP32ui_lp2sy_C1RxHdr;
        qlp_C1RxWrValid <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
        qlp_C1RxIrValid <= ffs_vl_LP32ui_lp2sy_C1RxIrValid;
    end


    // ====================================================================    
    //
    //  Construct the driver.
    //
    // ====================================================================    
    qa_drv_host_channel #(
         .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
         .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
         .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
         .CCI_TAG_WIDTH(CCI_TAG_WIDTH),
         .UMF_WIDTH(UMF_WIDTH)
        )
    host_channel
      (
       .clk,
       .qlp_resetb,
       .qlp_C0TxHdr,
       .qlp_C0TxRdValid,
       .qlp_C0TxAlmFull,
       .qlp_C1TxHdr,
       .qlp_C1TxData,
       .qlp_C1TxWrValid,
       .qlp_C1TxIrValid,
       .qlp_C1TxAlmFull,
       .qlp_C0RxHdr,
       .qlp_C0RxData,
       .qlp_C0RxWrValid,
       .qlp_C0RxRdValid,
       .qlp_C0RxCgValid,
       .qlp_C0RxUgValid,
       .qlp_C0RxIrValid,
       .qlp_C1RxHdr,
       .qlp_C1RxWrValid,
       .qlp_C1RxIrValid,
       .rx_fifo_data,   
       .rx_fifo_rdy,
       .rx_fifo_enable,
       .tx_fifo_data,
       .tx_fifo_rdy,
       .tx_fifo_enable,
       .sreg_req_addr,
       .sreg_req_rdy,
       .sreg_rsp,
       .sreg_rsp_enable
      );


endmodule
