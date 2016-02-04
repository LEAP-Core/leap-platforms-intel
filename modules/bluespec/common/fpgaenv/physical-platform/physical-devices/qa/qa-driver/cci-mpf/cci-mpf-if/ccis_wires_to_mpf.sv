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
import ccis_if_pkg::*;

module ccis_wires_to_mpf
  #(
    parameter REGISTER_INPUTS = 1,
    parameter REGISTER_OUTPUTS = 0,

    // CSR read compatibility mode address is the address of a CSR write
    // that triggers a CSR read.  Translate it here.
    parameter CSR_READ_COMPAT_ADDR = -1
    )
   (
    // -------------------------------------------------------------------
    //
    //   System interface.  These signals come directly from the CCI.
    //
    // -------------------------------------------------------------------

    input logic             vl_clk_LPdomain_32ui,                // CCI Inteface Clock. 32ui link/protocol clock domain.
    input logic             ffs_vl_LP32ui_lp2sy_SoftReset_n,     // CCI-S soft reset

    input  logic            vl_clk_LPdomain_16ui,                // 2x CCI interface clock. Synchronous.16ui link/protocol clock domain.
    input  logic            ffs_vl_LP32ui_lp2sy_SystemReset_n,   // System Reset

    // Native CCI Interface (cache line interface for back end)
    /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
    input  t_ccis_RspMemHdr ffs_vl18_LP32ui_lp2sy_C0RxHdr,       // System to LP header
    input  t_ccis_cldata    ffs_vl512_LP32ui_lp2sy_C0RxData,     // System to LP data 
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
    output t_ccis_cldata    ffs_vl512_LP32ui_sy2lp_C1TxData,     // System to LP data 
    output logic            ffs_vl_LP32ui_sy2lp_C1TxWrValid,     // TxWrHdr valid signal
    output logic            ffs_vl_LP32ui_sy2lp_C1TxIrValid,     // Tx Interrupt valid signal
    /* Tx push flow control */
    input  logic            ffs_vl_LP32ui_lp2sy_C0TxAlmFull,     // Channel 0 almost full
    input  logic            ffs_vl_LP32ui_lp2sy_C1TxAlmFull,     // Channel 1 almost full

    input  logic            ffs_vl_LP32ui_lp2sy_InitDnForSys,    // System layer is aok to run


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

    // CCI-S header from MPF header
    function t_ccis_ReqMemHdr cci_mpf_to_ccis_ReqMemHdr(t_cci_mpf_ReqMemHdr mpf_h);
        t_ccis_ReqMemHdr h;

        h = t_ccis_ReqMemHdr'(0);
        h.req_type = t_ccis_req'(mpf_h.base.req_type);
        h.address  = mpf_h.base.address;
        h.mdata    = mpf_h.base.mdata;
        return h;
    endfunction

    t_ccis_ReqMemHdr c0TxHdr;
    assign c0TxHdr = cci_mpf_to_ccis_ReqMemHdr(fiu_ext.c0Tx.hdr);
    t_ccis_ReqMemHdr c1TxHdr;
    assign c1TxHdr = cci_mpf_to_ccis_ReqMemHdr(fiu_ext.c1Tx.hdr);

    // Validate requests and responses
    always_ff @(posedge clk)
    begin
        if (! reset)
        begin
            if (fiu_ext.c0Tx.rdValid)
            begin
                assert(t_cci_claddr'(c0TxHdr.address) == fiu_ext.c0Tx.hdr.base.address) else
                    $fatal("ccis_wires_to_mpf.sv: c0TxHdr address truncated");
                assert(t_cci_mdata'(c0TxHdr.mdata) == fiu_ext.c0Tx.hdr.base.mdata) else
                    $fatal("ccis_wires_to_mpf.sv: c0TxHdr mdata truncated");
                assert(! fiu_ext.c0Tx.hdr.ext.addrIsVirtual) else
                    $fatal("ccis_wires_to_mpf.sv: c0TxHdr address is virtual");
                assert(fiu_ext.c0Tx.hdr.base.cl_num == 0) else
                    $fatal("ccis_wires_to_mpf.sv: c0TxHdr cl_num != 0");
            end

            if (fiu_ext.c1Tx.wrValid)
            begin
                assert(t_cci_claddr'(c1TxHdr.address) == fiu_ext.c1Tx.hdr.base.address) else
                    $fatal("ccis_wires_to_mpf.sv: c1TxHdr address truncated");
                assert(t_cci_mdata'(c1TxHdr.mdata) == fiu_ext.c1Tx.hdr.base.mdata) else
                    $fatal("ccis_wires_to_mpf.sv: c1TxHdr mdata truncated");
                assert(! fiu_ext.c1Tx.hdr.ext.addrIsVirtual) else
                    $fatal("ccis_wires_to_mpf.sv: c1TxHdr address is virtual");
                assert(fiu_ext.c1Tx.hdr.base.cl_num == 0) else
                    $fatal("ccis_wires_to_mpf.sv: c1TxHdr cl_num != 0");
            end

            assert(! ffs_vl_LP32ui_lp2sy_C0RxIrValid) else
                $fatal("ccis_wires_to_mpf.sv: ffs_vl_LP32ui_lp2sy_C0RxIrValid not supported");
        end
    end

    generate
        if (REGISTER_OUTPUTS)
        begin : reg_out
            always_ff @(posedge clk)
            begin
                ffs_vl61_LP32ui_sy2lp_C0TxHdr <= c0TxHdr;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid <= fiu_ext.c0Tx.rdValid;
                fiu_ext.c0TxAlmFull <= ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr <= c1TxHdr;
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
                ffs_vl61_LP32ui_sy2lp_C0TxHdr = c0TxHdr;
                ffs_vl_LP32ui_sy2lp_C0TxRdValid = fiu_ext.c0Tx.rdValid;
                fiu_ext.c0TxAlmFull = ffs_vl_LP32ui_lp2sy_C0TxAlmFull;

                ffs_vl61_LP32ui_sy2lp_C1TxHdr = c1TxHdr;
                ffs_vl512_LP32ui_sy2lp_C1TxData = fiu_ext.c1Tx.data;
                ffs_vl_LP32ui_sy2lp_C1TxWrValid = fiu_ext.c1Tx.wrValid;
                ffs_vl_LP32ui_sy2lp_C1TxIrValid = fiu_ext.c1Tx.intrValid;
                fiu_ext.c1TxAlmFull = ffs_vl_LP32ui_lp2sy_C1TxAlmFull;
            end
        end
    endgenerate


    //
    // Convert RX wires
    //

    // CCI-S header from MPF header
    function t_cci_RspMemHdr ccis_to_cci_RspMemHdr(t_ccis_RspMemHdr h_s);
        t_cci_RspMemHdr h;

        h = t_cci_RspMemHdr'(0);
        h.vc_used = eVC_VL0;
        h.resp_type = t_cci_rsp'(h_s.resp_type);
        h.mdata = t_cci_mdata'(h_s.mdata);
        return h;
    endfunction

    function t_cci_Req_MmioHdr ccis_to_cci_ReqMmioHdr(t_ccis_RspMemHdr h_s);
        t_cci_Req_MmioHdr h;

        h = t_cci_Req_MmioHdr'(0);
        h.address = t_ccip_mmioaddr'(h_s.mdata);

        // CSR read compatibility mode?  Read address is in data.
        if (h.address == CSR_READ_COMPAT_ADDR)
        begin
            h.address = t_ccip_mmioaddr'(ffs_vl512_LP32ui_lp2sy_C0RxData);
        end

        h.length = 2'b1;
        return h;
    endfunction

    t_cci_RspMemHdr c0RxHdr;
    assign c0RxHdr =
        ffs_vl_LP32ui_lp2sy_C0RxCgValid ?
            t_cci_RspMemHdr'(ccis_to_cci_ReqMmioHdr(ffs_vl18_LP32ui_lp2sy_C0RxHdr)) :
            ccis_to_cci_RspMemHdr(ffs_vl18_LP32ui_lp2sy_C0RxHdr);
    t_cci_RspMemHdr c1RxHdr;
    assign c1RxHdr = ccis_to_cci_RspMemHdr(ffs_vl18_LP32ui_lp2sy_C1RxHdr);

    //
    // Only 8 byte CSR writes are supported.  CCI-S only supports native 4
    // byte CSRs.  We get around this by retaining the previous write
    // and combining it when forwarding CSR writes.  The software writes
    // to a known empty CSR address to update the high part.
    //
    logic [31:0] csr_wr_high;
    always_ff @(posedge clk)
    begin
        if (ffs_vl_LP32ui_lp2sy_C0RxCgValid)
        begin
            csr_wr_high <= 32'(ffs_vl512_LP32ui_lp2sy_C0RxData);
        end
    end

    t_cci_cldata c0RxData;
    always_comb
    begin
        c0RxData = ffs_vl512_LP32ui_lp2sy_C0RxData;
        if (ffs_vl_LP32ui_lp2sy_C0RxCgValid)
        begin
            c0RxData[63:32] = csr_wr_high;
        end
    end

    logic c0RxCgValid;
    assign c0RxCgValid = ffs_vl_LP32ui_lp2sy_C0RxCgValid &&
                         (ffs_vl18_LP32ui_lp2sy_C0RxHdr.mdata != CSR_READ_COMPAT_ADDR);

    // CSR read?  Triggered using "compatibility mode" in which a CSR
    // write to a magic address triggers a read.
    logic csr_rd_en;
    assign csr_rd_en = ffs_vl_LP32ui_lp2sy_C0RxCgValid &&
                       (ffs_vl18_LP32ui_lp2sy_C0RxHdr.mdata == CSR_READ_COMPAT_ADDR);

    generate
        if (REGISTER_INPUTS)
        begin : reg_in
            always_ff @(posedge clk)
            begin
                fiu_ext.c0Rx.hdr         <= c0RxHdr;
                fiu_ext.c0Rx.data        <= c0RxData;
                fiu_ext.c0Rx.wrValid     <= ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu_ext.c0Rx.rdValid     <= ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu_ext.c0Rx.umsgValid   <= ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu_ext.c0Rx.mmioWrValid <= c0RxCgValid;
                fiu_ext.c0Rx.mmioRdValid <= csr_rd_en;

                fiu_ext.c1Rx.hdr         <= c1RxHdr;
                fiu_ext.c1Rx.wrValid     <= ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu_ext.c1Rx.intrValid   <= ffs_vl_LP32ui_lp2sy_C1RxIrValid;
            end
        end
        else
        begin : wire_in
            always_comb
            begin
                fiu_ext.c0Rx.hdr         = c0RxHdr;
                fiu_ext.c0Rx.data        = c0RxData;
                fiu_ext.c0Rx.wrValid     = ffs_vl_LP32ui_lp2sy_C0RxWrValid;
                fiu_ext.c0Rx.rdValid     = ffs_vl_LP32ui_lp2sy_C0RxRdValid;
                fiu_ext.c0Rx.umsgValid   = ffs_vl_LP32ui_lp2sy_C0RxUgValid;
                fiu_ext.c0Rx.mmioWrValid = c0RxCgValid;
                fiu_ext.c0Rx.mmioRdValid = csr_rd_en;

                fiu_ext.c1Rx.hdr         = c1RxHdr;
                fiu_ext.c1Rx.wrValid     = ffs_vl_LP32ui_lp2sy_C1RxWrValid;
                fiu_ext.c1Rx.intrValid   = ffs_vl_LP32ui_lp2sy_C1RxIrValid;
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
    t_ccis_mdata wr_rsp_mdata;
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
        .enq_data(t_ccis_mdata'(fiu_ext.c0Rx.hdr.mdata)),
        .enq_en(fiu_ext.c0Rx.wrValid),
        .first(wr_rsp_mdata),
        .deq_en(wr_rsp_deq_en),
        .notEmpty(wr_rsp_not_empty),
        .notFull(),
        .almostFull()
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
            fiu.c1Rx.hdr.mdata = t_cci_mdata'(wr_rsp_mdata);
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
