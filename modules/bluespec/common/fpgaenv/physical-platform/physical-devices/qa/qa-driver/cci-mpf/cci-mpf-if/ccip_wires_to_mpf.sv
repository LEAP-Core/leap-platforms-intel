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
    input  logic        vl_clk_LPdomain_16ui,       // CCI interface clock
    input  logic        vl_clk_LPdomain_64ui,       // 1/4x Frequency of interface clock. Synchronous.
    input  logic        vl_clk_LPdomain_32ui,       // 1/2x Frequency of interface clock. Synchronous.
    input  logic        ffs_LP16ui_afu_SoftReset_n, // CCI-P Soft Reset
    input  logic [1:0]  ffs_LP16ui_afu_PwrState,    // CCI-P AFU Power State
    input  logic        ffs_LP16ui_afu_Error,       // CCI-P Protocol Error Detected

    // Data ports
    output t_if_ccip_Tx ffs_LP16ui_sTxData_afu,     // CCI-P Tx Port
    input  t_if_ccip_Rx ffs_LP16ui_sRxData_afu,     // CCI-P Rx Port

    // -------------------------------------------------------------------
    //
    //   MPF interface.
    //
    // -------------------------------------------------------------------

    cci_mpf_if fiu
    );

    logic  clk;
    assign clk = vl_clk_LPdomain_16ui;

    assign fiu.reset_n = ffs_LP16ui_afu_SoftReset_n;

    generate
        if (REGISTER_OUTPUTS)
        begin : reg_out
            always_ff @(posedge clk)
            begin
                ffs_LP16ui_sTxData_afu.c0 <= cci_mpf_cvtC0TxToBase(fiu.c0Tx);
                ffs_LP16ui_sTxData_afu.c1 <= cci_mpf_cvtC1TxToBase(fiu.c1Tx);
                ffs_LP16ui_sTxData_afu.c2 <= fiu.c2Tx;

                fiu.c0TxAlmFull <= ffs_LP16ui_sRxData_afu.c0TxAlmFull;
                fiu.c1TxAlmFull <= ffs_LP16ui_sRxData_afu.c1TxAlmFull;
            end
        end
        else
        begin : wire_out
            always_comb
            begin
                ffs_LP16ui_sTxData_afu.c0 = cci_mpf_cvtC0TxToBase(fiu.c0Tx);
                ffs_LP16ui_sTxData_afu.c1 = cci_mpf_cvtC1TxToBase(fiu.c1Tx);
                ffs_LP16ui_sTxData_afu.c2 = fiu.c2Tx;

                fiu.c0TxAlmFull = ffs_LP16ui_sRxData_afu.c0TxAlmFull;
                fiu.c1TxAlmFull = ffs_LP16ui_sRxData_afu.c1TxAlmFull;
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
                fiu.c0Rx <= ffs_LP16ui_sRxData_afu.c0;
                fiu.c1Rx <= ffs_LP16ui_sRxData_afu.c1;
            end
        end
        else
        begin : wire_in
            always_comb
            begin
                fiu.c0Rx = ffs_LP16ui_sRxData_afu.c0;
                fiu.c1Rx = ffs_LP16ui_sRxData_afu.c1;
            end
        end
    endgenerate

endmodule // ccip_wires_to_mpf

`endif
