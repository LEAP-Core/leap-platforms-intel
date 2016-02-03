//
// Map CCI-S wires to the MPF interface.
//

//
// In addition to mapping CCI-S wires, this module adds a canonicalization layer
// that shifts all channel 0 write responses to channel 1.  This is the behavior
// of later CCI versions.
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

    // FIU connection to the external wires
    cci_mpf_if fiu_ext(.clk);

    logic reset;
    assign reset = ! (ffs_vl_LP32ui_lp2sy_SoftReset_n &&
                      ffs_vl_LP32ui_lp2sy_InitDnForSys);
    assign fiu_ext.reset = reset;
    assign fiu.reset = fiu_ext.reset;

    // Route AFU Tx lines toward FIU
    assign fiu_ext.c0Tx = fiu.c0Tx;
    assign fiu_ext.c1Tx = fiu.c1Tx;

    generate
        if (REGISTER_OUTPUTS)
        begin : reg_out
            always_ff @(posedge clk)
            begin
                ffs_vl61_LP32ui_sy2lp_C0TxHdr <= fiu_ext.c0Tx.hdr.base;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid <= fiu_ext.c0Tx.rdValid;
                fiu_ext.c0TxAlmFull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr <= fiu_ext.c1Tx.hdr.base;
                ffs_vl512_LP32ui_sy2lp_C1TxData <= fiu_ext.c1Tx.data;
                ffs_vl_LP32ui_sy2lp_C1TxWrValid <= fiu_ext.c1Tx.wrValid;
                ffs_vl_LP32ui_sy2lp_C1TxIrValid <= fiu_ext.c1Tx.intrValid;
                fiu_ext.c1TxAlmFull <= ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
            end
        end
        else
        begin : wire_out
            always_comb
            begin
                ffs_vl61_LP32ui_sy2lp_C0TxHdr = fiu_ext.c0Tx.hdr.base;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid = fiu_ext.c0Tx.rdValid;
                fiu_ext.c0TxAlmFull = ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr = fiu_ext.c1Tx.hdr.base;
                ffs_vl512_LP32ui_sy2lp_C1TxData = fiu_ext.c1Tx.data;
                ffs_vl_LP32ui_sy2lp_C1TxWrValid = fiu_ext.c1Tx.wrValid;
                ffs_vl_LP32ui_sy2lp_C1TxIrValid = fiu_ext.c1Tx.intrValid;
                fiu_ext.c1TxAlmFull = ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
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
                fiu_ext.c0Rx.hdr       <= ffs_vl18_LP32ui_lp2sy_C0RxHdr;
                fiu_ext.c0Rx.data      <= ffs_vl512_LP32ui_lp2sy_C0RxData;
                fiu_ext.c0Rx.wrValid   <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu_ext.c0Rx.rdValid   <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu_ext.c0Rx.cfgValid  <= ffs_vl_LP32ui_lp2sy_C0RxCgValid;
                fiu_ext.c0Rx.umsgValid <= ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu_ext.c0Rx.intrValid <= ffs_vl_LP32ui_lp2sy_C0RxIrValid;

                fiu_ext.c1Rx.hdr       <= ffs_vl18_LP32ui_lp2sy_C1RxHdr;
                fiu_ext.c1Rx.wrValid   <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu_ext.c1Rx.intrValid <= ffs_vl_LP32ui_lp2sy_C1RxIrValid;
            end
        end
        else
        begin : wire_in
            always_comb
            begin
                fiu_ext.c0Rx.hdr       = ffs_vl18_LP32ui_lp2sy_C0RxHdr;
                fiu_ext.c0Rx.data      = ffs_vl512_LP32ui_lp2sy_C0RxData;
                fiu_ext.c0Rx.wrValid   = ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu_ext.c0Rx.rdValid   = ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu_ext.c0Rx.cfgValid  = ffs_vl_LP32ui_lp2sy_C0RxCgValid;
                fiu_ext.c0Rx.umsgValid = ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu_ext.c0Rx.intrValid = ffs_vl_LP32ui_lp2sy_C0RxIrValid;

                fiu_ext.c1Rx.hdr       = ffs_vl18_LP32ui_lp2sy_C1RxHdr;
                fiu_ext.c1Rx.wrValid   = ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu_ext.c1Rx.intrValid = ffs_vl_LP32ui_lp2sy_C1RxIrValid;
            end
        end
    endgenerate


    //
    // Interfaces after CCI-S return write responses only on c1.  Move
    // all c0 write responses to c1.
    //

    // Limit write requests to the available response buffer space.
    localparam MAX_WRITE_REQS = 256;
    logic [$clog2(MAX_WRITE_REQS)-1 : 0] num_active_writes;

    logic wr_valid;
    assign wr_valid = (fiu.c1Tx.wrValid &&
                       ((fiu.c1Tx.hdr.base.req_type == eREQ_WRLINE_I) ||
                        (fiu.c1Tx.hdr.base.req_type == eREQ_WRLINE_M)));

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            num_active_writes <= 0;
        end
        else
        begin
            // The active write request count changes only when there
            // is a new request without a response or vice versa.

            if (wr_valid && ! fiu.c1Rx.wrValid)
            begin
                // New request without corresponding response
                num_active_writes <= num_active_writes + 1;
            end
            else if (! wr_valid && fiu.c1Rx.wrValid)
            begin
                // Response without corresponding new request
                num_active_writes <= num_active_writes - 1;
            end
        end
    end
    
    assign fiu.c0TxAlmFull = fiu_ext.c0TxAlmFull;
    // Signal full to avoid filling the write response FIFO
    assign fiu.c1TxAlmFull =
        fiu_ext.c1TxAlmFull ||
        (num_active_writes >= MAX_WRITE_REQS - CCI_ALMOST_FULL_THRESHOLD);


    //
    // Send c0 write responses to c1 instead.
    //
    t_cci_mdata wr_rsp_mdata;
    logic wr_rsp_deq_en;
    logic wr_rsp_not_empty;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(CCI_MDATA_WIDTH),
        .N_ENTRIES(MAX_WRITE_REQS)
        )
      c0_wr_rsp
       (
        .clk,
        .reset,
        .enq_data(fiu_ext.c0Rx.hdr.mdata),
        .enq_en(fiu_ext.c0Rx.wrValid),
        .first(wr_rsp_mdata),
        .deq_en(wr_rsp_deq_en),
        .notEmpty(wr_rsp_not_empty)
        );

    always_comb
    begin
        // Forward c0Rx but drop write responses, which go into the FIFO to
        // be routed to c1Rx.
        fiu.c0Rx = fiu_ext.c0Rx;
        fiu.c0Rx.wrValid = 1'b0;

        if (wr_rsp_not_empty && ! cci_c1RxIsValid(fiu_ext.c1Rx))
        begin
            fiu.c1Rx = t_if_cci_c1_Rx'(0);
            fiu.c1Rx.hdr.resp_type = eRSP_WRLINE;
            fiu.c1Rx.hdr.mdata = wr_rsp_mdata;
            fiu.c1Rx.wrValid = 1'b1;

            wr_rsp_deq_en = 1'b1;
        end
        else
        begin
            fiu.c1Rx = fiu_ext.c1Rx;
            wr_rsp_deq_en = 1'b0;
        end
    end

endmodule // ccis_wires_to_mpf

`endif
