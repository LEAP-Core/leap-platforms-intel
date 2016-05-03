// ***************************************************************************
//
//        Copyright (C) 2008-2015 Intel Corporation All Rights Reserved.
//
// Engineer :           Pratik Marolia
// Creation Date :      20-05-2015
// Last Modified :      Wed 20 May 2015 03:03:09 PM PDT
// Module Name :        ccip_std_afu
// Project :        ccip afu top (work in progress)
// Description :    This module instantiates CCI-P compliant AFU

// ***************************************************************************
import ccip_if_pkg::*;
`include "cci_mpf_if.vh"

module ccip_std_afu(
  // CCI-P Clocks and Resets
  input           logic             pClk,              // 400MHz - CCI-P clock domain. Primary interface clock
  input           logic             pClkDiv2,          // 200MHz - CCI-P clock domain.
  input           logic             pClkDiv4,          // 100MHz - CCI-P clock domain.
  input           logic             uClk_usr,          // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
  input           logic             uClk_usrDiv2,      // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
  input           logic             pck_cp2af_softReset,      // CCI-P ACTIVE HIGH Soft Reset
  input           logic [1:0]       pck_cp2af_pwrState,       // CCI-P AFU Power State
  input           logic             pck_cp2af_error,          // CCI-P Protocol Error Detected

  // Interface structures
  input           t_if_ccip_Rx      pck_cp2af_sRx,        // CCI-P Rx Port
  output          t_if_ccip_Tx      pck_af2cp_sTx         // CCI-P Tx Port
);
// Expose FIU as an MPF interface
//
localparam MPF_DFH_MMIO_ADDR = 'h1000;


// Async shim 
logic 	  reset_pass;   
   logic 	  afu_clk;   

   t_if_ccip_Tx mpf_tx;
   t_if_ccip_Rx mpf_rx;
      
   //assign afu_clk = uClk_usrDiv2;
	assign afu_clk = pClkDiv4;
   
   ccip_async_shim ccip_async_shim (
				    .bb_softreset    (pck_cp2af_softReset),
				    .bb_clk          (pClk),
				    .bb_tx           (pck_af2cp_sTx),
				    .bb_rx           (pck_cp2af_sRx),
				    .afu_softreset   (reset_pass),
				    .afu_clk         (afu_clk),
				    .afu_tx          (mpf_tx),
				    .afu_rx          (mpf_rx)
				    );

cci_mpf_if fiu(.clk(afu_clk));

ccip_wires_to_mpf
  #(
    .REGISTER_INPUTS(0),
    .REGISTER_OUTPUTS(1)
    )
  map_ifc(.pClk(afu_clk),                // 400MHz - CCI-P clock domain. Primary interface clock
    .pClkDiv2(pClkDiv2),            // 200MHz - CCI-P clock domain.
    .pClkDiv4(pClkDiv4),            // 100MHz - CCI-P clock domain.
    .uClk_usr(afu_clk),            // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
    .uClk_usrDiv2((afu_clk)),        // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
    .pck_cp2af_softReset(reset_pass), // CCI-P ACTIVE HIGH Soft Reset
    .pck_cp2af_pwrState(pck_cp2af_pwrState),  // CCI-P AFU Power State
    .pck_cp2af_error(pck_cp2af_error),     // CCI-P Protocol Error Detected

    // Interface structures
    .pck_cp2af_sRx(mpf_rx),       // CCI-P Rx Port
    .pck_af2cp_sTx(mpf_tx ),       // CCI-P Tx Port

    // -------------------------------------------------------------------
    //
    //   MPF interface.
    //
    // -------------------------------------------------------------------

   .fiu(fiu));


//
// Put MPF between AFU and FIU.
//
cci_mpf_if afu(.clk(afu_clk));

cci_mpf
  #(
    .SORT_READ_RESPONSES(1),
    .PRESERVE_WRITE_MDATA(1),

    // Don't enforce write/write or write/read ordering within a cache line.
    // (Default CCI behavior.)
    .ENFORCE_WR_ORDER(0),

    // Address of the MPF feature header
    .DFH_MMIO_BASE_ADDR(MPF_DFH_MMIO_ADDR)
    )
  mpf
   (
    .clk(afu_clk),
    .fiu,
    .afu
    );

t_if_ccip_Tx nlb_tx;
t_if_ccip_Rx nlb_rx;
always_comb
begin
    nlb_rx.c0 = afu.c0Rx;
    nlb_rx.c1 = afu.c1Rx;

    nlb_rx.c0TxAlmFull = afu.c0TxAlmFull;
    nlb_rx.c1TxAlmFull = afu.c1TxAlmFull;

    afu.c0Tx = cci_mpf_cvtC0TxFromBase(nlb_tx.c0);
    // Treat all addresses as virtual
    if (cci_mpf_c0TxIsReadReq(afu.c0Tx))
    begin
        afu.c0Tx.hdr.ext.addrIsVirtual = 1'b1;
    end

    afu.c1Tx = cci_mpf_cvtC1TxFromBase(nlb_tx.c1);
    if (cci_mpf_c1TxIsWriteReq(afu.c1Tx))
    begin
        afu.c1Tx.hdr.ext.addrIsVirtual = 1'b1;
    end

    afu.c2Tx = nlb_tx.c2;
end


//===============================================================================================
// User AFU goes here
//===============================================================================================
// NLB AFU- provides validation, performance characterization modes. It also serves as a reference design
nlb_lpbk#(.MPF_DFH_MMIO_ADDR(MPF_DFH_MMIO_ADDR))
 nlb_lpbk(
  .Clk_400             ( afu_clk ) ,
  .SoftReset           ( reset_pass) ,

  .cp2af_sRxPort       ( nlb_rx ) ,
  .af2cp_sTxPort       ( nlb_tx ) 
);

// ccip_debug is a reference debug module for tapping cci-p signals
/*
ccip_debug inst_ccip_debug(
  .pClk                (pClk),        
  .pck_cp2af_pwrState  (pck_cp2af_pwrState),
  .pck_cp2af_error     (pck_cp2af_error),

  .pck_cp2af_sRx       (pck_cp2af_sRx),   
  .pck_af2cp_sTx       (pck_af2cp_sTx)    
);
*/


endmodule
