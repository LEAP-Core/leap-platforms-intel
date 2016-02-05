//
// Map CCI-P wires to the MPF interface.
//

`include "cci_mpf_if.vh"

`ifdef USE_PLATFORM_CCIP

module ccip_wires_to_mpf
  #(
    parameter REGISTER_INPUTS = 1,
    parameter REGISTER_OUTPUTS = 0
    )
   (
    // -------------------------------------------------------------------
    //
    //   System interface.  These signals come directly from the CCI.
    //
    // -------------------------------------------------------------------

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
    output t_if_ccip_Tx pck_af2cp_sTx,       // CCI-P Tx Port

    // -------------------------------------------------------------------
    //
    //   MPF interface.
    //
    // -------------------------------------------------------------------

    cci_mpf_if fiu
    );

    logic  clk;
    assign clk = pClk;

    assign fiu.reset = pck_cp2af_softReset;

    generate
        if (REGISTER_OUTPUTS)
        begin : reg_out
            always_ff @(posedge clk)
            begin
                pck_af2cp_sTx.c0 <= cci_mpf_cvtC0TxToBase(fiu.c0Tx);
                pck_af2cp_sTx.c1 <= cci_mpf_cvtC1TxToBase(fiu.c1Tx);
                pck_af2cp_sTx.c2 <= fiu.c2Tx;

                fiu.c0TxAlmFull <= pck_cp2af_sRx.c0TxAlmFull;
                fiu.c1TxAlmFull <= pck_cp2af_sRx.c1TxAlmFull;
            end
        end
        else
        begin : wire_out
            always_comb
            begin
                pck_af2cp_sTx.c0 = cci_mpf_cvtC0TxToBase(fiu.c0Tx);
                pck_af2cp_sTx.c1 = cci_mpf_cvtC1TxToBase(fiu.c1Tx);
                pck_af2cp_sTx.c2 = fiu.c2Tx;

                fiu.c0TxAlmFull = pck_cp2af_sRx.c0TxAlmFull;
                fiu.c1TxAlmFull = pck_cp2af_sRx.c1TxAlmFull;
            end
        end
    endgenerate

    //
    // Buffer incoming read responses for timing
    //
    generate
        if (REGISTER_INPUTS)
        begin : reg_in
            always_ff @(posedge clk)
            begin
                fiu.c0Rx <= pck_cp2af_sRx.c0;
                fiu.c1Rx <= pck_cp2af_sRx.c1;
            end
        end
        else
        begin : wire_in
            always_comb
            begin
                fiu.c0Rx = pck_cp2af_sRx.c0;
                fiu.c1Rx = pck_cp2af_sRx.c1;
            end
        end
    endgenerate

endmodule // ccip_wires_to_mpf

`endif
