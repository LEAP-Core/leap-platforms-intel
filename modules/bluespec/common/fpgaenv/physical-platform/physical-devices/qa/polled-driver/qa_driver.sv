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

// Compile all the packages.
`include "qa_drv_packages.vh"

`include "qa.vh"

module qa_driver
  #(parameter TXHDR_WIDTH=61,
              RXHDR_WIDTH=18,
              CACHE_WIDTH=512,
              UMF_WIDTH=128)
    (input logic vl_clk_LPdomain_32ui,                      // CCI Inteface Clock. 32ui link/protocol clock domain.
     input logic ffs_vl_LP32ui_lp2sy_SoftReset_n,           // CCI-S soft reset

     // -------------------------------------------------------------------
     //
     //   Client interface
     //
     // -------------------------------------------------------------------

     // To client FIFO
     output logic [UMF_WIDTH-1:0] rx_fifo_data,   
     output logic                 rx_fifo_rdy,
     input  logic                 rx_fifo_enable,
    
     // From client FIFO
     input  logic [UMF_WIDTH-1:0] tx_fifo_data,
     output logic                 tx_fifo_rdy,
     input  logic                 tx_fifo_enable,

     // -------------------------------------------------------------------
     //
     //   System interface.  These signals come directly from the CCI.
     //
     // -------------------------------------------------------------------

     input  logic                   vl_clk_LPdomain_16ui,                // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
     input  logic                   ffs_vl_LP32ui_lp2sy_SystemReset_n,   // System Reset

     // Native CCI Interface (cache line interface for back end)
     /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
     input  logic [RXHDR_WIDTH-1:0] ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
     input  logic [CACHE_WIDTH-1:0] ffs_vl512_LP32ui_lp2sy_C0RxData,     // System to LP data 
     input  logic                   ffs_vl_LP32ui_lp2sy_C0RxWrValid,     // RxWrHdr valid signal 
     input  logic                   ffs_vl_LP32ui_lp2sy_C0RxRdValid,     // RxRdHdr valid signal
     input  logic                   ffs_vl_LP32ui_lp2sy_C0RxCgValid,     // RxCgHdr valid signal
     input  logic                   ffs_vl_LP32ui_lp2sy_C0RxUgValid,     // Rx Umsg Valid signal
     input  logic                   ffs_vl_LP32ui_lp2sy_C0RxIrValid,     // Rx Interrupt valid signal
     /* Channel 1 reserved for WRITE RESPONSE ONLY */
     input  logic [RXHDR_WIDTH-1:0] ffs_vl18_LP32ui_lp2sy_C1RxHdr,       // System to LP header (Channel 1)
     input  logic                   ffs_vl_LP32ui_lp2sy_C1RxWrValid,     // RxData valid signal (Channel 1)
     input  logic                   ffs_vl_LP32ui_lp2sy_C1RxIrValid,     // Rx Interrupt valid signal (Channel 1)

     /*Channel 0 reserved for READ REQUESTS ONLY */        
     output logic [TXHDR_WIDTH-1:0] ffs_vl61_LP32ui_sy2lp_C0TxHdr,       // System to LP header 
     output logic                   ffs_vl_LP32ui_sy2lp_C0TxRdValid,     // TxRdHdr valid signals 
     /*Channel 1 reserved for WRITE REQUESTS ONLY */       
     output logic [TXHDR_WIDTH-1:0] ffs_vl61_LP32ui_sy2lp_C1TxHdr,       // System to LP header
     output logic [CACHE_WIDTH-1:0] ffs_vl512_LP32ui_sy2lp_C1TxData,     // System to LP data 
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

    logic  resetb;
    assign resetb = ffs_vl_LP32ui_lp2sy_SoftReset_n;

    rx_c0_t rx0;
    assign rx0.header     = ffs_vl18_LP32ui_lp2sy_C0RxHdr;
    assign rx0.data       = ffs_vl512_LP32ui_lp2sy_C0RxData;
    assign rx0.wrvalid    = ffs_vl_LP32ui_lp2sy_C0RxWrValid;
    assign rx0.rdvalid    = ffs_vl_LP32ui_lp2sy_C0RxRdValid;
    assign rx0.cfgvalid   = ffs_vl_LP32ui_lp2sy_C0RxCgValid;

    rx_c1_t rx1;
    assign rx1.header     = ffs_vl18_LP32ui_lp2sy_C1RxHdr;
    assign rx1.wrvalid    = ffs_vl_LP32ui_lp2sy_C1RxWrValid;

    logic  tx0_almostfull;
    assign tx0_almostfull = ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

    logic  tx1_almostfull;
    assign tx1_almostfull = ffs_vl_LP32ui_lp2sy_C1TxAlmFull;

    logic  lp_initdone;
    assign lp_initdone = ffs_vl_LP32ui_lp2sy_InitDnForSys;

    //
    // Outputs are registered, as required by the CCI specification.
    //
    tx_c0_t tx0;
    tx_c0_t tx0_reg;
    tx_c1_t tx1;
    tx_c1_t tx1_reg;

    assign ffs_vl61_LP32ui_sy2lp_C0TxHdr = tx0_reg.header;
    assign ffs_vl_LP32ui_sy2lp_C0TxRdValid = tx0_reg.rdvalid;

    assign ffs_vl61_LP32ui_sy2lp_C1TxHdr = tx1_reg.header;
    assign ffs_vl512_LP32ui_sy2lp_C1TxData = tx1_reg.data;
    assign ffs_vl_LP32ui_sy2lp_C1TxWrValid = tx1_reg.wrvalid;

    assign ffs_vl_LP32ui_sy2lp_C1TxIrValid = 1'b0;

    //
    // All signals to the host must come from registers.  Guarantee that here.
    //
    always_ff @(posedge vl_clk_LPdomain_32ui)
    begin
        if (! ffs_vl_LP32ui_lp2sy_SystemReset_n)
        begin
            tx0_reg.rdvalid <= 0;
            tx1_reg.wrvalid <= 0;
        end
        else
        begin
            tx0_reg <= tx0;
            tx1_reg <= tx1;
        end
    end


    // ====================================================================
    //
    // Internal module wiring.
    //
    // ====================================================================

    // FIFO wires inside the driver.  They will be mapped to the wires
    // exported to the client in the qa_drv_tester module.
    logic [UMF_WIDTH-1:0]  rx_data;
    logic                  rx_rdy;
    logic                  rx_enable;
    logic [UMF_WIDTH-1:0]  tx_data;
    logic                  tx_rdy;
    logic                  tx_enable;

    t_CSR_AFU_STATE        csr;
    
    frame_arb_t            frame_writer;
    frame_arb_t            frame_reader;
    frame_arb_t            status_writer;
    channel_grant_arb_t    write_grant;
    channel_grant_arb_t    read_grant;
    
    t_AFU_DEBUG_RSP        dbg_fifo_from_host;
    t_AFU_DEBUG_RSP        dbg_frame_release;
    t_AFU_DEBUG_RSP        dbg_tester;

    // Map FIFO wires exported by the driver to the driver's internal wiring.
    // Normally the signals just pass through, but the tester can be
    // configured by CSR writes into a variety of loopback and traffic generator
    // modes.
    qa_drv_tester#(.UMF_WIDTH(UMF_WIDTH))
        qa_tester_inst(.*);

    // Consume CSR writes and export state to the driver.
    qa_drv_csr qa_csr_inst(.*);

    // Manage memory-mapped FIFOs in each direction.
    qa_drv_fifo_from_host  fifo_from_host(.*);
    qa_drv_fifo_to_host    fifo_to_host(.*);

    qa_drv_status_writer   status_writer_inst(.*);
    cci_write_arbiter      write_arb(.*);
    cci_read_arbiter       read_arb(.*);
    
endmodule
