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

`include "qa_driver.vh"

module qa_driver
  #(
    parameter CCI_ADDR_WIDTH = 32,
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,
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
    // Memory read
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_read_req_addr,
    output logic                      mem_read_req_rdy,
    input  logic                      mem_read_req_enable,

    output logic [CCI_DATA_WIDTH-1:0] mem_read_rsp_data,
    output logic                      mem_read_rsp_rdy,

    //
    // Memory write request
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_write_addr,
    input  logic [CCI_DATA_WIDTH-1:0] mem_write_data,
    output logic                      mem_write_rdy,
    input  logic                      mem_write_enable,

    // Write ACK count.  Pulse with a count every time writes completes.
    // Multiple writes may complete in a single cycle.
    output logic [1:0]                mem_write_ack,

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

    logic  clk;
    assign clk = vl_clk_LPdomain_32ui;

    // ====================================================================
    //
    //   Map the CCI driver interface to the qlp_interface used by the
    //   composable components in the driver.  All I/O ports are
    //   registered here for timing.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      qlp(.clk);

    assign qlp.resetb = ffs_vl_LP32ui_lp2sy_SoftReset_n &&
                        ffs_vl_LP32ui_lp2sy_InitDnForSys;

    //
    // Buffer outgoing write requests for timing
    //
    always_ff @(posedge clk)
    begin
        ffs_vl61_LP32ui_sy2lp_C0TxHdr <= qlp.C0TxHdr;
        ffs_vl_LP32ui_sy2lp_C0TxRdValid <= qlp.C0TxRdValid;
        qlp.C0TxAlmFull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

        ffs_vl61_LP32ui_sy2lp_C1TxHdr <= qlp.C1TxHdr;
        ffs_vl512_LP32ui_sy2lp_C1TxData <= qlp.C1TxData;
        ffs_vl_LP32ui_sy2lp_C1TxWrValid <= qlp.C1TxWrValid;
        ffs_vl_LP32ui_sy2lp_C1TxIrValid <= qlp.C1TxIrValid;
        qlp.C1TxAlmFull <= ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
    end

    //
    // Buffer incoming read responses for timing
    //
    always_ff @(posedge clk)
    begin
        qlp.C0RxHdr     <= ffs_vl18_LP32ui_lp2sy_C0RxHdr;
        qlp.C0RxData    <= ffs_vl512_LP32ui_lp2sy_C0RxData;
        qlp.C0RxWrValid <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
        qlp.C0RxRdValid <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
        qlp.C0RxCgValid <= ffs_vl_LP32ui_lp2sy_C0RxCgValid;
        qlp.C0RxUgValid <= ffs_vl_LP32ui_lp2sy_C0RxUgValid;
        qlp.C0RxIrValid <= ffs_vl_LP32ui_lp2sy_C0RxIrValid;

        qlp.C1RxHdr     <= ffs_vl18_LP32ui_lp2sy_C1RxHdr;
        qlp.C1RxWrValid <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
        qlp.C1RxIrValid <= ffs_vl_LP32ui_lp2sy_C1RxIrValid;
    end


    // ====================================================================    
    //
    //  Parse CSR messages.
    //
    // ====================================================================    

    t_CSR_AFU_STATE csr;
    qa_driver_csr
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      csr_mgr
        (.clk,
         .qlp,
         .csr);


    // ====================================================================    
    //
    //  Split the connection into a pair of interfaces that will be
    //  routed to separate clients.  One client will be used for
    //  a direct memory interface.  The other will implement a pair
    //  of memory mapped channels: one from the host and one from the
    //  FPGA.
    //
    // ====================================================================    

    localparam MUX_IDX_MEMORY   = 0;
    localparam MUX_IDX_CHANNELS = 1;

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      qlp_mux[0:1] (.clk);

    qa_shim_mux
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH),
        .MUX_MDATA_IDX(CCI_TAG_WIDTH-1)
        )
      mux
       (
        .clk,
        .qlp,
        .afus(qlp_mux)
        );


    // ====================================================================    
    //
    //  Connect the memory driver.
    //
    // ====================================================================    

    qa_drv_memory
      #(
        .CCI_ADDR_WIDTH(CCI_ADDR_WIDTH),
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      host_memory
       (
        .clk,
        .qlp(qlp_mux[MUX_IDX_MEMORY]),
        .mem_read_req_addr,
        .mem_read_req_rdy,
        .mem_read_req_enable,
        .mem_read_rsp_data,
        .mem_read_rsp_rdy,
        .mem_write_addr,
        .mem_write_data,
        .mem_write_rdy,
        .mem_write_enable,
        .mem_write_ack
        );


    // ====================================================================    
    //
    //  Connect the channel driver.
    //
    // ====================================================================    

    qa_drv_host_channel
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH),
        .UMF_WIDTH(UMF_WIDTH)
        )
      host_channel
       (
        .clk,
        .qlp(qlp_mux[MUX_IDX_CHANNELS]),
        .csr,
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
