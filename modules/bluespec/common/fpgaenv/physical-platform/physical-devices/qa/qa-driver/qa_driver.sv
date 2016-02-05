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


// ========================================================================
//
//   Compose a memory interface and host/FPGA channel over the CCI
//   for Xeon+FPGA. There are three sets of wires in the driver:
//
//     1.  A client interface to a bidirectional host/FPGA latency
//         insensitive channel. The channel operates at the width
//         of a cache line and provides a simple FIFO. Clients of
//         the channel are free to layer any protocol on top of the
//         base FIFO primitive.
//
//     2.  A client interface to system memory, exposed as simple
//         read and write requests. In the configuration here addresses
//         are virtual and translated by the TLB shim, instantiated
//         below. The constructed memory system guarantees that stores
//         to the same line remain ordered. Loads and stores to the same
//         line are also ordered. No order is guaranteed between
//         references to distinct lines.
//
//     3.  A system interface that must be tied to the CCI driver
//         provided by Intel. The topology constructed here connects
//         to CCI-S -- the interface that employs physical addresses
//         for memory references.
//
// ========================================================================

`include "qa_driver_csr.vh"

`ifdef USE_PLATFORM_CCIS
import ccis_if_pkg::*;
`endif

module qa_driver
  #(
    parameter CCI_ADDR_WIDTH = 56
    )
   (
    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    //
    // To client FIFO
    //
    output t_cci_clData rx_fifo_data,
    output logic        rx_fifo_rdy,
    input  logic        rx_fifo_enable,
   
    //
    // From client FIFO
    //
    input  t_cci_clData tx_fifo_data,
    output logic        tx_fifo_rdy,
    input  logic        tx_fifo_enable,

    //
    // Memory read
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_read_req_addr,
    // Use CCI's cache if true
    input  logic        mem_read_req_cached,
    // Enforce order of references to the same address?
    input  logic        mem_read_req_check_order,
    output logic        mem_read_req_rdy,
    input  logic        mem_read_req_enable,

    output t_cci_clData mem_read_rsp_data,
    output logic        mem_read_rsp_rdy,

    //
    // Memory write request
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_write_addr,
    input  t_cci_clData mem_write_data,
    // Use CCI's cache if true
    input  logic        mem_write_req_cached,
    // Enforce order of references to the same address?
    input  logic        mem_write_req_check_order,
    output logic        mem_write_rdy,
    input  logic        mem_write_enable,

    // Write ACK count.  Pulse with a count every time writes completes.
    // Multiple writes may complete in a single cycle.
    output logic [1:0]  mem_write_ack,

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
    output [31:0]       sreg_req_addr,
    output logic        sreg_req_rdy,
    input  [63:0]       sreg_rsp,
    input  logic        sreg_rsp_enable,

    // -------------------------------------------------------------------
    //
    //   System interface.  These signals come directly from the CCI.
    //
    // -------------------------------------------------------------------

`ifdef USE_PLATFORM_CCIS
    input  logic            vl_clk_LPdomain_32ui,                // CCI Inteface Clock. 32ui link/protocol clock domain.
    input  logic            ffs_vl_LP32ui_lp2sy_SoftReset_n,     // CCI-S soft reset

    input  logic            vl_clk_LPdomain_16ui,                // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
    input  logic            ffs_vl_LP32ui_lp2sy_SystemReset_n,   // System Reset

    // Native CCI Interface (cache line interface for back end)
    /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
    input  t_ccis_RspMemHdr ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
    input  t_ccis_clData    ffs_vl512_LP32ui_lp2sy_C0RxData, // System to LP data 
    input  logic            ffs_vl_LP32ui_lp2sy_C0RxWrValid,     // RxWrHdr valid signal 
    input  logic            ffs_vl_LP32ui_lp2sy_C0RxRdValid,     // RxRdHdr valid signal
    input  logic            ffs_vl_LP32ui_lp2sy_C0RxCgValid,     // RxCgHdr valid signal
    input  logic            ffs_vl_LP32ui_lp2sy_C0RxUgValid,     // Rx Umsg Valid signal
    input  logic            ffs_vl_LP32ui_lp2sy_C0RxIrValid,     // Rx Interrupt valid signal
    /* Channel 1 reserved for WRITE RESPONSE ONLY */
    input  t_ccis_RspMemHdr ffs_vl18_LP32ui_lp2sy_C1RxHdr,       // System to LP header (Channel 1)
    input  logic            ffs_vl_LP32ui_lp2sy_C1RxWrValid,     // RxData valid signal (Channel 1)
    input  logic            ffs_vl_LP32ui_lp2sy_C1RxIrValid,     // Rx Interrupt valid signal (Channel 1)

    /*Channel 0 reserved for READ REQUESTS ONLY */        
    output t_ccis_ReqMemHdr ffs_vl61_LP32ui_sy2lp_C0TxHdr,       // System to LP header 
    output logic            ffs_vl_LP32ui_sy2lp_C0TxRdValid,     // TxRdHdr valid signals 
    /*Channel 1 reserved for WRITE REQUESTS ONLY */       
    output t_ccis_ReqMemHdr ffs_vl61_LP32ui_sy2lp_C1TxHdr,       // System to LP header
    output t_ccis_clData    ffs_vl512_LP32ui_sy2lp_C1TxData, // System to LP data 
    output logic            ffs_vl_LP32ui_sy2lp_C1TxWrValid,     // TxWrHdr valid signal
    output logic            ffs_vl_LP32ui_sy2lp_C1TxIrValid,     // Tx Interrupt valid signal
    /* Tx push flow control */
    input  logic            ffs_vl_LP32ui_lp2sy_C0TxAlmFull,     // Channel 0 almost full
    input  logic            ffs_vl_LP32ui_lp2sy_C1TxAlmFull,     // Channel 1 almost full

    input  logic            ffs_vl_LP32ui_lp2sy_InitDnForSys     // System layer is aok to run
`endif

`ifdef USE_PLATFORM_CCIP
    // CCI-P Clocks and Resets
    input  logic        pClk,                // 400MHz - CCI-P clock domain. Primary interface clock
    input  logic        pClkDiv2,            // 200MHz - CCI-P clock domain.
    input  logic        pClkDiv4,            // 100MHz - CCI-P clock domain.
    input  logic        uClk_usr,            // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
    input  logic        uClk_usrDiv2,        // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
    input  logic        pck_cp2af_softReset, // CCI-P ACTIVE HIGH Soft Reset
    input  logic [1:0]  pck_cp2af_pwrState,  // CCI-P AFU Power State
    input  logic        pck_cp2af_error,     // CCI-P Protocol Error Detected

    // Interface structures
    input  t_if_ccip_Rx pck_cp2af_sRx,       // CCI-P Rx Port
    output t_if_ccip_Tx pck_af2cp_sTx        // CCI-P Tx Port
`endif

    );

    localparam AFU_ID = 128'h13572468_0d824272_9aeffe5f_84570612;

    logic  clk;
`ifdef USE_PLATFORM_CCIS
    assign clk = vl_clk_LPdomain_32ui;
`endif
`ifdef USE_PLATFORM_CCIP
    assign clk = pClk;
`endif


    // ====================================================================
    //
    // Make sure exposed interface matches the memory system!
    //
    // ====================================================================

    // Virtual addresses exposed to the client
    initial begin
        assert (CCI_ADDR_WIDTH == CCI_MPF_CLADDR_WIDTH) else
            $fatal("qa_driver.sv expects CCI_ADDR_WIDTH %d but configured with %d",
                   CCI_MPF_CLADDR_WIDTH, CCI_ADDR_WIDTH);
    end


    // ====================================================================
    //
    //   Map the CCI driver interface to the cci_mpf_if used by the
    //   composable components in the driver.
    //
    // ====================================================================

    cci_mpf_if#(.ENABLE_LOG(1)) fiu(.clk);

`ifdef USE_PLATFORM_CCIS
    ccis_wires_to_mpf
      #(
        .REGISTER_INPUTS(0),
        .REGISTER_OUTPUTS(1),
        .CSR_READ_COMPAT_ADDR(CSR_AFU_MMIO_READ_COMPAT >> 2)
        )
      map_ifc(.*);
`endif

`ifdef USE_PLATFORM_CCIP
    ccip_wires_to_mpf
      #(
        .REGISTER_INPUTS(0),
        .REGISTER_OUTPUTS(1)
        )
      map_ifc(.*);
`endif


    // ====================================================================
    //
    //   Add a tap to the FIU where the driver can inject messages to the
    //   host and filter some responses.
    //
    // ====================================================================

    cci_mpf_if fiu_main(.clk);
    t_csr_afu_state csr;

    qa_driver_main_fiu_tap
      #(
        .AFU_ID(AFU_ID),
        .QA_DRIVER_WRITE_TAG((1 << CCI_MDATA_WIDTH) - 1)
        )
      tap
       (
        .clk,
        .fiu,
        .afu(fiu_main),
        .csr
        );


    // ====================================================================    
    //
    //  Parse CSR messages.
    //
    // ====================================================================    

    // Writes from host to FPGA CSRs
    qa_driver_csr_wr
      csr_mgr_wr
       (
        .clk,
        .fiu(fiu_main),
        .csr);

    // CSR read responses, generated by csr_mgr_rd
    t_if_cci_c2_Tx afu_csr_rd_rsp;

    // Reads from host from FPGA CSRs
    qa_driver_csr_rd
       #(
         .AFU_ID(AFU_ID)
         )
      csr_mgr_rd
       (
        .clk,
        .fiu(fiu_main),
        .c2Tx(afu_csr_rd_rsp),
        .sreg_req_rdy,
        .sreg_rsp,
        .sreg_rsp_enable
        );

    // Forward status register read requests
    assign sreg_req_addr = csr.afu_sreg_addr;


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

    cci_mpf_if
      fiu_mux[0:1] (.clk);

    cci_mpf_shim_mux
      #(
        // Route c2Tx from memory path
        .C2TX_INPUT_CHANNEL(MUX_IDX_MEMORY),

        // The bit in Mdata that the MUX code will use to record the source
        // of requests. This Mdata location but be 0 on all requests
        // arriving at the MUX.
        .RESERVED_MDATA_IDX(CCI_MDATA_WIDTH-1)
        )
      mux
       (
        .clk,
        .fiu(fiu_main),
        .afus(fiu_mux)
        );


    // ====================================================================    
    //
    //  Connect the memory driver.
    //
    // ====================================================================    

    qa_driver_memory
      host_memory
       (
        .clk,
        .fiu(fiu_mux[MUX_IDX_MEMORY]),
        .afu_mmio_rd_rsp(afu_csr_rd_rsp),
        .mem_read_req_addr,
        .mem_read_req_cached,
        .mem_read_req_check_order,
        .mem_read_req_rdy,
        .mem_read_req_enable,
        .mem_read_rsp_data,
        .mem_read_rsp_rdy,
        .mem_write_addr,
        .mem_write_data,
        .mem_write_req_cached,
        .mem_write_req_check_order,
        .mem_write_rdy,
        .mem_write_enable,
        .mem_write_ack
        );


    // ====================================================================    
    //
    //  Connect the channel driver.
    //
    // ====================================================================    

    qa_drv_hc_root
      #(
        // Host channel CSR base address must match the software side,
        // defined in AFU_csr.h.
        .CSR_HC_BASE_ADDR('h1a80)
        )
      host_channel
       (
        .clk,
        .fiu(fiu_mux[MUX_IDX_CHANNELS]),
        .rx_fifo_data,
        .rx_fifo_rdy,
        .rx_fifo_enable,
        .tx_fifo_data,
        .tx_fifo_rdy,
        .tx_fifo_enable
        );

endmodule
