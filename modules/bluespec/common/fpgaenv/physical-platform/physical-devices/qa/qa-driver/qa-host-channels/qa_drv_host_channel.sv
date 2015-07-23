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

module qa_drv_host_channel
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 14,
    parameter UMF_WIDTH=128
    )
   (
    input  logic                        clk,

    //
    // Signals connecting to QA Platform
    //

    input  logic                        qlp_resetb,

    // Requests to QLP
    output logic [CCI_TX_HDR_WIDTH-1:0] qlp_C0TxHdr,
    output logic                        qlp_C0TxRdValid,
    input  logic                        qlp_C0TxAlmFull,

    output logic [CCI_TX_HDR_WIDTH-1:0] qlp_C1TxHdr,
    output logic [CCI_DATA_WIDTH-1:0]   qlp_C1TxData,
    output logic                        qlp_C1TxWrValid,
    output logic                        qlp_C1TxIrValid,
    input  logic                        qlp_C1TxAlmFull,

    // Responses from QLP
    input  logic [CCI_RX_HDR_WIDTH-1:0] qlp_C0RxHdr,
    input  logic [CCI_DATA_WIDTH-1:0]   qlp_C0RxData,
    input  logic                        qlp_C0RxWrValid,
    input  logic                        qlp_C0RxRdValid,
    input  logic                        qlp_C0RxCgValid,
    input  logic                        qlp_C0RxUgValid,
    input  logic                        qlp_C0RxIrValid,

    input  logic [CCI_RX_HDR_WIDTH-1:0] qlp_C1RxHdr,
    input  logic                        qlp_C1RxWrValid,
    input  logic                        qlp_C1RxIrValid,

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
    input  logic                 sreg_rsp_enable
    );

    //
    // The driver uses structures and shorter names to group the CCI.
    // Map names here.
    //
    logic  resetb;
    assign resetb = qlp_resetb;

    t_RX_C0 rx0;
    // Buffer incoming read responses for timing
    always_ff @(posedge clk)
    begin
        rx0.header     <= qlp_C0RxHdr;
        rx0.data       <= qlp_C0RxData;
        rx0.wrvalid    <= qlp_C0RxWrValid;
        rx0.rdvalid    <= qlp_C0RxRdValid;
        rx0.cfgvalid   <= qlp_C0RxCgValid;
    end

    t_RX_C1 rx1;
    always_ff @(posedge clk)
    begin
        rx1.header     <= qlp_C1RxHdr;
        rx1.wrvalid    <= qlp_C1RxWrValid;
    end

    logic  tx0_almostfull;
    logic  tx1_almostfull;
    always_ff @(posedge clk)
    begin
        tx0_almostfull <= qlp_C0TxAlmFull;
        tx1_almostfull <= qlp_C1TxAlmFull;
    end

    //
    // Outputs are registered, as required by the CCI specification.
    //
    t_TX_C0 tx0;
    t_TX_C0 tx0_reg;
    t_TX_C1 tx1;
    t_TX_C1 tx1_reg;

    assign qlp_C0TxHdr = tx0_reg.header;
    assign qlp_C0TxRdValid = tx0_reg.rdvalid;

    assign qlp_C1TxHdr = tx1_reg.header;
    assign qlp_C1TxData = tx1_reg.data;
    assign qlp_C1TxWrValid = tx1_reg.wrvalid;

    assign qlp_C1TxIrValid = 1'b0;

    //
    // All signals to the host must come from registers.  Guarantee that here.
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
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
