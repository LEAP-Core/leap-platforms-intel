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



localparam MPF_DFH_MMIO_ADDR = 'h1000;

//
// Expose FIU as an MPF interface
//
cci_mpf_if fiu(.clk(pClk));

ccip_wires_to_mpf
  #(
    .REGISTER_INPUTS(0),
    .REGISTER_OUTPUTS(1)
    )
  map_ifc(.*);

//
// Put MPF between AFU and FIU.
//
cci_mpf_if afu(.clk(pClk));

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
    .clk(pClk),
    .fiu,
    .afu
    );

t_if_ccip_Rx afu_rx;
t_if_ccip_Tx afu_tx;

always_comb
begin
    afu_rx.c0 = afu.c0Rx;
    afu_rx.c1 = afu.c1Rx;

    afu_rx.c0TxAlmFull = afu.c0TxAlmFull;
    afu_rx.c1TxAlmFull = afu.c1TxAlmFull;

    afu.c0Tx = cci_mpf_cvtC0TxFromBase(afu_tx.c0);
    // Treat all addresses as virtual
    if (cci_mpf_c0TxIsReadReq(afu.c0Tx))
    begin
        afu.c0Tx.hdr.ext.addrIsVirtual = 1'b1;
    end

    afu.c1Tx = cci_mpf_cvtC1TxFromBase(afu_tx.c1);
    if (cci_mpf_c1TxIsWriteReq(afu.c1Tx))
    begin
        afu.c1Tx.hdr.ext.addrIsVirtual = 1'b1;
    end

    afu.c2Tx = afu_tx.c2;
end


//===============================================================================================
// User AFU goes here
//===============================================================================================
// NLB AFU- provides validation, performance characterization modes. It also serves as a reference design
   nlb_lpbk
     // #(
     //   .MPF_DFH_MMIO_ADDR(MPF_DFH_MMIO_ADDR)
     //   )
   nlb_lpbk(
	    .Clk_400             ( pClk ) ,
	    .SoftReset           ( pck_cp2af_softReset ) ,
	    
	    .cp2af_sRxPort       ( afu_rx ) ,
	    .af2cp_sTxPort       ( afu_tx ) 
	    );
   
endmodule
