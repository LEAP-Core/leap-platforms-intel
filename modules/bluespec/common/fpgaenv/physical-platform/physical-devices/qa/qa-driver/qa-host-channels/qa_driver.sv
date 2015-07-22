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
     output t_SREG_ADDR           sreg_req_addr,
     output logic                 sreg_req_rdy,
     input  t_SREG                sreg_rsp,
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
     input  logic [RXHDR_WIDTH-1:0] ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
     input  logic [QA_CACHE_LINE_SZ-1:0] ffs_vl512_LP32ui_lp2sy_C0RxData, // System to LP data 
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
     output logic [QA_CACHE_LINE_SZ-1:0] ffs_vl512_LP32ui_sy2lp_C1TxData, // System to LP data 
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

    t_RX_C0 rx0;
    // Buffer incoming read responses for timing
    always_ff @(posedge vl_clk_LPdomain_32ui)
    begin
        rx0.header     <= ffs_vl18_LP32ui_lp2sy_C0RxHdr;
        rx0.data       <= ffs_vl512_LP32ui_lp2sy_C0RxData;
        rx0.wrvalid    <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
        rx0.rdvalid    <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
        rx0.cfgvalid   <= ffs_vl_LP32ui_lp2sy_C0RxCgValid;
    end

    t_RX_C1 rx1;
    always_ff @(posedge vl_clk_LPdomain_32ui)
    begin
        rx1.header     <= ffs_vl18_LP32ui_lp2sy_C1RxHdr;
        rx1.wrvalid    <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
    end

    logic  tx0_almostfull;
    logic  tx1_almostfull;
    logic  lp_initdone;
    always_ff @(posedge vl_clk_LPdomain_32ui)
    begin
        tx0_almostfull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;
        tx1_almostfull <= ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
        lp_initdone    <= ffs_vl_LP32ui_lp2sy_InitDnForSys;
    end

    //
    // Outputs are registered, as required by the CCI specification.
    //
    t_TX_C0 tx0;
    t_TX_C0 tx0_reg;
    t_TX_C1 tx1;
    t_TX_C1 tx1_reg;

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
    
    t_FRAME_ARB            frame_writer;
    t_FRAME_ARB            frame_reader;
    t_FRAME_ARB            status_mgr_req;
    t_CHANNEL_GRANT_ARB    write_grant;
    t_CHANNEL_GRANT_ARB    read_grant;
    
    // Modules communicating state to the status manager
    t_TO_STATUS_MGR_FIFO_FROM_HOST   fifo_from_host_to_status;
    t_FROM_STATUS_MGR_FIFO_FROM_HOST status_to_fifo_from_host;

    t_TO_STATUS_MGR_FIFO_TO_HOST     fifo_to_host_to_status;
    t_FROM_STATUS_MGR_FIFO_TO_HOST   status_to_fifo_to_host;

    t_TO_STATUS_MGR_TESTER           tester_to_status;


    // Map FIFO wires exported by the driver to the driver's internal wiring.
    // Normally the signals just pass through, but the tester can be
    // configured by CSR writes into a variety of loopback and traffic generator
    // modes.
    qa_drv_tester#(.UMF_WIDTH(UMF_WIDTH))          qa_tester_inst(.*);

    // Consume CSR writes and export state to the driver.
    qa_drv_csr                                     qa_csr_inst(.*);

    // Manage memory-mapped FIFOs in each direction.
    qa_drv_fifo_from_host#(.UMF_WIDTH(UMF_WIDTH))  fifo_from_host(.*);
    qa_drv_fifo_to_host#(.UMF_WIDTH(UMF_WIDTH))    fifo_to_host(.*);

    qa_drv_status_manager                          status_manager(.*);
    cci_write_arbiter                              write_arb(.*);
    cci_read_arbiter                               read_arb(.*);
    
endmodule
