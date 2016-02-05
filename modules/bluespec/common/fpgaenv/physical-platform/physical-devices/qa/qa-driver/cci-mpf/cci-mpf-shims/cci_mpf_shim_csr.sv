//
// Copyright (c) 2016, Intel Corporation
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

`include "cci_mpf_if.vh"
`include "cci_mpf_csrs.vh"

//
// There is a single CSR (MMIO read/write) manager in MPF, shared by all
// shims.  We do this because the required buffering is large enough to be
// worth sharing across all shims.  When a shim is not present in a
// system the corresponding CSRs have no meaning.
//

module cci_mpf_shim_csr
  #(
    // MMIO base address (byte level) allocated to MPF for feature lists
    // and CSRs.  The AFU allocating this module must build at least
    // a device feature header (DFH) for the AFU.  The chain of device
    // features in the AFU must then point to the base address here
    // as another feature in the chain.  MPF will continue the list.
    // The base address here must point to a region that is at least
    // CCI_MPF_MMIO_SIZE bytes.
    parameter DFH_MMIO_BASE_ADDR = 0,

    // Address of the next device feature header outside MPF.  MPF will
    // terminate the feature list if the next address is 0.
    parameter DFH_MMIO_NEXT_ADDR = 0,

    // Is shims enabled?
    parameter MPF_ENABLE_VTP = 0,
    parameter MPF_ENABLE_WRO = 0
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    // CSR connections to other shims
    cci_mpf_csrs.csr csrs
    );

    logic reset;
    assign reset = fiu.reset;
    assign afu.reset = fiu.reset;

    // Most connections flow straight through and are, at most, read in this shim.
    assign fiu.c0Tx = afu.c0Tx;
    assign afu.c0TxAlmFull = fiu.c0TxAlmFull;
    assign fiu.c1Tx = afu.c1Tx;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull;

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;


    // MMIO address range of MPF CSRs
    localparam CCI_MPF_CSR_SIZE     = CCI_MPF_VTP_CSR_SIZE + CCI_MPF_WRO_CSR_SIZE;
    localparam CCI_MPF_CSR_LAST     = DFH_MMIO_BASE_ADDR + CCI_MPF_CSR_SIZE;

    // Base address of each shim's CSR range
    localparam CCI_MPF_VTP_CSR_BASE = DFH_MMIO_BASE_ADDR;
    localparam CCI_MPF_WRO_CSR_BASE = CCI_MPF_VTP_CSR_BASE + CCI_MPF_VTP_CSR_SIZE;
    
    // Offset of each shim's CSR range from feature list start.  This is
    // similar to base addresses above, but the origin is the first feature
    // managed by MPF.
    localparam CCI_MPF_VTP_CSR_OFFSET = 0;
    localparam CCI_MPF_WRO_CSR_OFFSET = CCI_MPF_VTP_CSR_OFFSET + CCI_MPF_VTP_CSR_SIZE;

    // Type for holding MPF CSR address as an offset from DFH_MMIO_BASE_ADDR
    typedef logic [$clog2(CCI_MPF_CSR_SIZE)-1:0] t_mpf_csr_offset;


    // ====================================================================
    //
    //  CSR writes from host to FPGA
    //
    // ====================================================================

    // Check for a CSR address match
    function automatic logic csrAddrMatches(
        input t_if_cci_c0_Rx c0Rx,
        input int c);

        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioAddr tgt = t_cci_mmioAddr'(c >> 2);

        // Actual address sent in CSR write.
        t_cci_mmioAddr addr = cci_csr_getAddress(c0Rx);

        return cci_csr_isWrite(c0Rx) && (addr == tgt);
    endfunction

    //
    // VTP CSR writes (host to FPGA)
    //
    t_cci_clAddr page_table_base;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            csrs.vtp_in_mode <= t_cci_mpf_vtp_csr_mode'(0);
            csrs.vtp_in_page_table_base_valid <= 1'b0;
        end
        else if (cci_csr_isWrite(fiu.c0Rx))
        begin
            if (csrAddrMatches(fiu.c0Rx, CCI_MPF_VTP_CSR_BASE +
                                         CCI_MPF_VTP_CSR_MODE))
            begin
                 csrs.vtp_in_mode <= t_cci_mpf_vtp_csr_mode'(fiu.c0Rx.data);
            end
            else if (csrAddrMatches(fiu.c0Rx, CCI_MPF_VTP_CSR_BASE +
                                              CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR))
            begin
                csrs.vtp_in_page_table_base <= t_cci_clAddr'(fiu.c0Rx.data);
                csrs.vtp_in_page_table_base_valid <= 1'b1;
            end
        end
    end


    // ====================================================================
    //
    //  CSR reads from host
    //
    // ====================================================================


    // Read responses flow through an outbound FIFO for timing
    t_if_ccip_c2_Tx c2_rsp_in;
    t_if_ccip_c2_Tx c2_rsp;
    logic c2_rsp_en;
    logic may_read;
    logic c2_rsp_deq;
    logic c2_rsp_rdy;

    cci_mpf_prim_fifo1
      #(
        .N_DATA_BITS($bits(t_if_ccip_c2_Tx))
        )
      rd_rsp_fifo
       (
        .clk,
        .reset,
        .enq_data(c2_rsp_in),
        .enq_en(c2_rsp_en),
        .notFull(may_read),
        .first(c2_rsp),
        .deq_en(c2_rsp_deq),
        .notEmpty(c2_rsp_rdy)
        );

    // Give priority to existing MMIO responses from the AFU
    assign c2_rsp_deq = ! afu.c2Tx.mmioRdValid && c2_rsp_rdy;
    
    // Forward responses to host
    always_ff @(posedge clk)
    begin
        fiu.c2Tx <= (c2_rsp_deq ? c2_rsp : afu.c2Tx);
    end

    logic mmio_req_valid;
    t_mpf_csr_offset mmio_req_addr;
    t_ccip_tid mmio_req_tid;

    t_mpf_csr_offset csr_addr;
    assign csr_addr = mmio_req_addr;

    // Is CSR read enabled and is the address in the appropriate range?
    logic is_csr_read;
    assign is_csr_read = mmio_req_valid;

    // Actually handling a response?
    assign c2_rsp_en = may_read && is_csr_read;

    always_comb
    begin
        t_ccip_dfh vtp_dfh;
        logic [127:0] vtp_uid;
        t_ccip_dfh wro_dfh;
        logic [127:0] wro_uid;

        // Construct the feature headers for each feature
        vtp_dfh = ccip_dfh_defaultDFH();
        vtp_dfh.f_type = eFTYP_BBB;
        vtp_dfh.next = CCI_MPF_VTP_CSR_SIZE;
        if (MPF_ENABLE_VTP != 0)
        begin
            // UID of VTP feature (from cci_mpf_csrs.h)
            vtp_uid = 128'hc8a2982f_ff96_42bf_a705_45727f501901;
        end
        else
        begin
            vtp_uid = 128'h0;
        end

        wro_dfh = ccip_dfh_defaultDFH();
        wro_dfh.f_type = eFTYP_BBB;
        if (MPF_ENABLE_WRO != 0)
        begin
            // UID of WRO feature (from cci_mpf_csrs.h)
            wro_uid = 128'h56b06b48_9dd7_4004_a47e_0681b4207a6d;
        end
        else
        begin
            wro_uid = 128'h0;
        end

        if (DFH_MMIO_NEXT_ADDR == 0)
        begin
            // WRO is the last feature in the AFU's list
            wro_dfh.next = CCI_MPF_WRO_CSR_SIZE;
            wro_dfh.eol = 1'b1;
        end
        else
        begin
            // Point to the next feature (outside of MPF)
            wro_dfh.next = DFH_MMIO_NEXT_ADDR - CCI_MPF_WRO_CSR_BASE;
        end

        //
        // Unconditional logic, controlled by c2_rsp_en
        //

        c2_rsp_in.hdr.tid = mmio_req_tid;

        // Address here has been converted to be relative to the start
        // of the MPF feature list.
        case (csr_addr)
          (CCI_MPF_VTP_CSR_OFFSET +
           CCI_MPF_VTP_CSR_DFH) >> 2: // VTP DFH (device feature header)
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = vtp_dfh;
            end
          (CCI_MPF_VTP_CSR_OFFSET +
           CCI_MPF_VTP_CSR_ID_L) >> 2: // VTP UID low
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = vtp_uid[63:0];
            end
          (CCI_MPF_VTP_CSR_OFFSET +
           CCI_MPF_VTP_CSR_ID_H) >> 2: // VTP UID high
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = vtp_uid[127:64];
            end

          (CCI_MPF_WRO_CSR_OFFSET +
           CCI_MPF_WRO_CSR_DFH) >> 2: // WRO DFH (device feature header)
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = wro_dfh;
            end
          (CCI_MPF_WRO_CSR_OFFSET +
           CCI_MPF_WRO_CSR_ID_L) >> 2: // WRO UID low
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = wro_uid[63:0];
            end
          (CCI_MPF_WRO_CSR_OFFSET +
           CCI_MPF_WRO_CSR_ID_H) >> 2: // WRO UID high
            begin
                c2_rsp_in.mmioRdValid = 1'b1;
                c2_rsp_in.data = wro_uid[127:64];
            end
        endcase
    end


    //
    // This platform has MMIO.  Up to 64 MMIO reads may be in flight.
    // Buffer incoming read requests since the read response port
    // contends with other responders.
    //

    // Register incoming requests
    t_if_cci_c0_Rx c0_rx;
    always_ff @(posedge clk)
    begin
        c0_rx <= fiu.c0Rx;
    end

    logic mmio_req_enq_en;
    logic mmio_req_not_full;

    // Address of incoming request
    t_cci_mmioAddr mmio_req_addr_in;
    assign mmio_req_addr_in = cci_csr_getAddress(c0_rx);

    t_cci_mmioAddr mmio_req_addr_in_offset;
    assign mmio_req_addr_in_offset = mmio_req_addr_in -
                                     t_cci_mmioAddr'(DFH_MMIO_BASE_ADDR >> 2);

    // Store incoming requests only if the address is possibly in range
    assign mmio_req_enq_en = cci_csr_isRead(c0_rx) &&
                             mmio_req_addr_in >= (DFH_MMIO_BASE_ADDR >> 2) &&
                             mmio_req_addr_in < (CCI_MPF_CSR_LAST >> 2);

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_mpf_csr_offset) + CCIP_TID_WIDTH),
        .N_ENTRIES(64)
        )
      req_fifo
        (
         .clk,
         .reset,
         // Store only the MMIO address bits needed for decode
         .enq_data({ t_mpf_csr_offset'(mmio_req_addr_in_offset),
                     cci_csr_getTid(c0_rx) }),
         .enq_en(mmio_req_enq_en),
         .notFull(mmio_req_not_full),
         .almostFull(),
         .first({mmio_req_addr, mmio_req_tid}),
         .deq_en(c2_rsp_en),
         .notEmpty(mmio_req_valid)
         );

endmodule // cci_mpf_shim_csr
