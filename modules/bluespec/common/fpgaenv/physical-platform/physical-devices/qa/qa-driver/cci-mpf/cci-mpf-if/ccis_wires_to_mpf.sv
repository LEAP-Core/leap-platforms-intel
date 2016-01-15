//
// Map CCI-S wires to the MPF interface.
//

`include "cci_mpf_if.vh"

`ifdef USE_PLATFORM_CCIS

module ccis_wires_to_mpf
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

    input logic            vl_clk_LPdomain_32ui,                // CCI Inteface Clock. 32ui link/protocol clock domain.
    input logic            ffs_vl_LP32ui_lp2sy_SoftReset_n,     // CCI-S soft reset

    input  logic           vl_clk_LPdomain_16ui,                // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
    input  logic           ffs_vl_LP32ui_lp2sy_SystemReset_n,   // System Reset

    // Native CCI Interface (cache line interface for back end)
    /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
    input  t_cci_RspMemHdr ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
    input  t_cci_cldata    ffs_vl512_LP32ui_lp2sy_C0RxData,     // System to LP data 
    input  logic           ffs_vl_LP32ui_lp2sy_C0RxWrValid,     // RxWrHdr valid signal 
    input  logic           ffs_vl_LP32ui_lp2sy_C0RxRdValid,     // RxRdHdr valid signal
    input  logic           ffs_vl_LP32ui_lp2sy_C0RxCgValid,     // RxCgHdr valid signal
    input  logic           ffs_vl_LP32ui_lp2sy_C0RxUgValid,     // Rx Umsg Valid signal
    input  logic           ffs_vl_LP32ui_lp2sy_C0RxIrValid,     // Rx Interrupt valid signal
    /* Channel 1 reserved for WRITE RESPONSE ONLY */
    input  t_cci_RspMemHdr ffs_vl18_LP32ui_lp2sy_C1RxHdr,       // System to LP header (Channel 1)
    input  logic           ffs_vl_LP32ui_lp2sy_C1RxWrValid,     // RxData valid signal (Channel 1)
    input  logic           ffs_vl_LP32ui_lp2sy_C1RxIrValid,     // Rx Interrupt valid signal (Channel 1)

    /*Channel 0 reserved for READ REQUESTS ONLY */        
    output t_cci_ReqMemHdr ffs_vl61_LP32ui_sy2lp_C0TxHdr,       // System to LP header 
    output logic           ffs_vl_LP32ui_sy2lp_C0TxRdValid,     // TxRdHdr valid signals 
    /*Channel 1 reserved for WRITE REQUESTS ONLY */       
    output t_cci_ReqMemHdr ffs_vl61_LP32ui_sy2lp_C1TxHdr,       // System to LP header
    output t_cci_cldata    ffs_vl512_LP32ui_sy2lp_C1TxData,     // System to LP data 
    output logic           ffs_vl_LP32ui_sy2lp_C1TxWrValid,     // TxWrHdr valid signal
    output logic           ffs_vl_LP32ui_sy2lp_C1TxIrValid,     // Tx Interrupt valid signal
    /* Tx push flow control */
    input  logic           ffs_vl_LP32ui_lp2sy_C0TxAlmFull,     // Channel 0 almost full
    input  logic           ffs_vl_LP32ui_lp2sy_C1TxAlmFull,     // Channel 1 almost full

    input  logic           ffs_vl_LP32ui_lp2sy_InitDnForSys,    // System layer is aok to run


    // -------------------------------------------------------------------
    //
    //   MPF interface.
    //
    // -------------------------------------------------------------------

    cci_mpf_if fiu
    );

    logic  clk;
    assign clk = vl_clk_LPdomain_32ui;

    assign fiu.reset_n = ffs_vl_LP32ui_lp2sy_SoftReset_n &&
                         ffs_vl_LP32ui_lp2sy_InitDnForSys;

    generate
        if (REGISTER_OUTPUTS)
        begin : reg_out
            always_ff @(posedge clk)
            begin
                ffs_vl61_LP32ui_sy2lp_C0TxHdr <= fiu.c0Tx.hdr.base;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid <= fiu.c0Tx.rdValid;
                fiu.c0TxAlmFull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr <= fiu.c1Tx.hdr.base;
                ffs_vl512_LP32ui_sy2lp_C1TxData <= fiu.c1Tx.data;
                ffs_vl_LP32ui_sy2lp_C1TxWrValid <= fiu.c1Tx.wrValid;
                ffs_vl_LP32ui_sy2lp_C1TxIrValid <= fiu.c1Tx.intrValid;
                fiu.c1TxAlmFull <= ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
            end
        end
        else
        begin : wire_out
            always_comb
            begin
                ffs_vl61_LP32ui_sy2lp_C0TxHdr = fiu.c0Tx.hdr.base;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid = fiu.c0Tx.rdValid;
                fiu.c0TxAlmFull = ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr = fiu.c1Tx.hdr.base;
                ffs_vl512_LP32ui_sy2lp_C1TxData = fiu.c1Tx.data;
                ffs_vl_LP32ui_sy2lp_C1TxWrValid = fiu.c1Tx.wrValid;
                ffs_vl_LP32ui_sy2lp_C1TxIrValid = fiu.c1Tx.intrValid;
                fiu.c1TxAlmFull = ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
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
                fiu.c0Rx.hdr       <= ffs_vl18_LP32ui_lp2sy_C0RxHdr;
                fiu.c0Rx.data      <= ffs_vl512_LP32ui_lp2sy_C0RxData;
                fiu.c0Rx.wrValid   <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu.c0Rx.rdValid   <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu.c0Rx.cfgValid  <= ffs_vl_LP32ui_lp2sy_C0RxCgValid;
                fiu.c0Rx.umsgValid <= ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu.c0Rx.intrValid <= ffs_vl_LP32ui_lp2sy_C0RxIrValid;

                fiu.c1Rx.hdr       <= ffs_vl18_LP32ui_lp2sy_C1RxHdr;
                fiu.c1Rx.wrValid   <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu.c1Rx.intrValid <= ffs_vl_LP32ui_lp2sy_C1RxIrValid;
            end
        end
        else
        begin : wire_in
            always_comb
            begin
                fiu.c0Rx.hdr       = ffs_vl18_LP32ui_lp2sy_C0RxHdr;
                fiu.c0Rx.data      = ffs_vl512_LP32ui_lp2sy_C0RxData;
                fiu.c0Rx.wrValid   = ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu.c0Rx.rdValid   = ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu.c0Rx.cfgValid  = ffs_vl_LP32ui_lp2sy_C0RxCgValid;
                fiu.c0Rx.umsgValid = ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu.c0Rx.intrValid = ffs_vl_LP32ui_lp2sy_C0RxIrValid;

                fiu.c1Rx.hdr       = ffs_vl18_LP32ui_lp2sy_C1RxHdr;
                fiu.c1Rx.wrValid   = ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu.c1Rx.intrValid = ffs_vl_LP32ui_lp2sy_C1RxIrValid;
            end
        end
    endgenerate

endmodule // ccis_wires_to_mpf

`endif
