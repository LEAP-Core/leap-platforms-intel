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

`include "cci_mpf_if.vh"
`include "qa_drv_hc.vh"


module qa_drv_hc_root
  #(
    // Start of the CSR region for the host channel
    parameter CSR_HC_BASE_ADDR = 0,

    // Which virtual channel should be used?
    parameter MEM_VIRTUAL_CHANNEL = 3  // eVC_VH1
    )
   (
    input  logic                 clk,

    //
    // Signals connecting to QA Platform
    //
    cci_mpf_if.to_fiu            fiu,

    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    //
    // To client FIFO
    //
    output t_cci_cldata rx_fifo_data,
    output logic        rx_fifo_rdy,
    input  logic        rx_fifo_enable,

    //
    // From client FIFO
    //
    input  t_cci_cldata tx_fifo_data,
    output logic        tx_fifo_rdy,
    input  logic        tx_fifo_enable
    );

    //
    // The driver uses structures and shorter names to group the CCI.
    // Map names here.
    //
    logic  reset_n;
    assign reset_n = fiu.reset_n;

    t_if_cci_c0_Rx rx0;
    // Buffer incoming read responses for timing
    always_ff @(posedge clk)
    begin
        rx0 <= fiu.c0Rx;
    end

    logic  tx0_almostfull;
    logic  tx1_almostfull;
    always_ff @(posedge clk)
    begin
        tx0_almostfull <= fiu.c0TxAlmFull;
        tx1_almostfull <= fiu.c1TxAlmFull;
    end

    //
    // Outputs are registered, as required by the CCI specification.
    //
    t_if_cci_c0_Tx tx0;
    t_if_cci_c0_Tx tx0_q;
    t_if_cci_c1_Tx tx1;
    t_if_cci_c1_Tx tx1_q;

    assign fiu.c0Tx = cci_mpf_cvtC0TxFromBase(tx0_q);
    assign fiu.c1Tx = cci_mpf_cvtC1TxFromBase(tx1_q);
    assign fiu.c2Tx = t_if_cci_c2_Tx'(0);

    //
    // All signals to the host must come from registers.  Guarantee that here.
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            tx0_q <= cci_c0TxClearValids();
            tx1_q <= cci_c1TxClearValids();
        end
        else
        begin
            tx0_q <= tx0;
            tx1_q <= tx1;
        end
    end


    // ====================================================================
    //
    // CSR management
    //
    // ====================================================================

    t_qa_drv_hc_csrs csr;

    qa_drv_hc_csr
      #(
        .CSR_HC_BASE_ADDR(CSR_HC_BASE_ADDR)
        )
      hcCsr
       (
        .clk,
        .reset_n,
        .c0Rx(rx0),
        .csr
        );


    // ====================================================================
    //
    // Internal module wiring.
    //
    // ====================================================================

    // FIFO wires inside the driver.  They will be mapped to the wires
    // exported to the client in the qa_drv_tester module.
    t_cci_cldata rx_data;
    logic        rx_rdy;
    logic        rx_enable;

    t_cci_cldata tx_data;
    logic        tx_rdy;
    logic        tx_enable;

    t_frame_arb            frame_writer;
    t_frame_arb            frame_reader;
    t_frame_arb            status_mgr_req;
    t_channel_grant_arb    write_grant;
    t_channel_grant_arb    read_grant;
    
    // Modules communicating state to the status manager
    t_to_status_mgr_fifo_from_host   fifo_from_host_to_status;
    t_from_status_mgr_fifo_from_host status_to_fifo_from_host;

    t_to_status_mgr_fifo_to_host     fifo_to_host_to_status;
    t_from_status_mgr_fifo_to_host   status_to_fifo_to_host;

    t_to_status_mgr_tester           tester_to_status;


    // Map FIFO wires exported by the driver to the driver's internal wiring.
    // Normally the signals just pass through, but the tester can be
    // configured by CSR writes into a variety of loopback and traffic generator
    // modes.
    qa_drv_hc_tester
      qa_tester_inst(.*);

    // Manage memory-mapped FIFOs in each direction.
    qa_drv_hc_fifo_from_host
      #(
        .MEM_VIRTUAL_CHANNEL(MEM_VIRTUAL_CHANNEL)
        )
      fifo_from_host(.*);

    qa_drv_hc_fifo_to_host
      #(
        .MEM_VIRTUAL_CHANNEL(MEM_VIRTUAL_CHANNEL)
        )
      fifo_to_host(.*);

    qa_drv_hc_status_manager
      #(
        .MEM_VIRTUAL_CHANNEL(MEM_VIRTUAL_CHANNEL)
        )
      status_manager(.*);

    qa_drv_hc_read_arbiter    read_arb(.*);
    qa_drv_hc_write_arbiter   write_arb(.*);
    
endmodule
