//
// Copyright (c) 2015, Intel Corporation
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
`include "qa_driver_csr.vh"


module qa_driver_memory
   (
    input  logic              clk,

    //
    // Signals connecting to QA Platform
    //
    cci_mpf_if.to_fiu         fiu,

    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    // MMIO read response from AFU.
    input  t_if_cci_c2_Tx     afu_mmio_rd_rsp,

    //
    // Memory read
    //
    input  t_cci_clAddr       mem_read_req_addr,
    // Number of lines requested in multi-line read
    input  t_cci_clLen        mem_read_req_num_lines,
    // Use CCI's cache if true
    input  logic              mem_read_req_cached,
    // Enforce order of references to the same address?
    input  logic              mem_read_req_check_order,
    output logic              mem_read_req_rdy,
    input  logic              mem_read_req_enable,

    output t_cci_clData       mem_read_rsp_data,
    output logic              mem_read_rsp_rdy,

    //
    // Memory write request
    //
    input  t_cci_clAddr       mem_write_addr,
    input  t_cci_clData       mem_write_data,
    // Number of lines written in multi-line read
    input  t_cci_clLen        mem_write_req_num_lines,
    // Start of packet?  (0 only for all but first beat in multi-line write)
    input  logic              mem_write_req_sop,
    // Use CCI's cache if true
    input  logic              mem_write_req_cached,
    // Enforce order of references to the same address?
    input  logic              mem_write_req_check_order,
    output logic              mem_write_rdy,
    input  logic              mem_write_enable,

    // Write ACK count.  Pulse with a count every time writes completes.
    // Multiple writes may complete in a single cycle.
    output logic [1:0]        mem_write_ack
    );

    logic  reset;
    assign reset = fiu.reset;

    // ====================================================================
    //
    //   Map client memory interface to the MPF interface.
    //
    // ====================================================================

    cci_mpf_if#(.ENABLE_LOG(1)) afu_if(.clk);

    t_cci_mpf_ReqMemHdrParams rd_req_params;
    always_comb
    begin
        rd_req_params = cci_mpf_defaultReqHdrParams(1);

        // Let MPF pick the channel
        rd_req_params.vc_sel = eVC_VA;
        rd_req_params.mapVAtoPhysChannel = 1'b1;

        rd_req_params.cl_len = mem_read_req_num_lines;
        rd_req_params.checkLoadStoreOrder = mem_read_req_check_order;
    end

    // Tag requests.  This is pointless since they come back ordered but useful
    // for debugging.
    t_cci_mdata_platform read_req_tag;
    t_cci_mdata_platform read_rsp_tag;
    t_cci_mdata_platform write_req_tag;
    t_cci_mdata_platform write_req_tag_next;

    always_ff @(posedge clk)
    begin
        afu_if.c0Tx <=
            cci_mpf_genC0TxReadReq(
                cci_mpf_c0_genReqHdr(mem_read_req_cached ? eREQ_RDLINE_S : eREQ_RDLINE_I,
                                     mem_read_req_addr,
                                     t_cci_mdata'(read_req_tag),
                                     rd_req_params),
                mem_read_req_enable);
    end

    assign mem_read_req_rdy = ! afu_if.c0TxAlmFull;

    assign mem_read_rsp_data = afu_if.c0Rx.data;
    assign mem_read_rsp_rdy = cci_c0Rx_isReadRsp(afu_if.c0Rx);


    t_cci_mpf_ReqMemHdrParams wr_req_params;
    always_comb
    begin
        wr_req_params = cci_mpf_defaultReqHdrParams();

        // Let MPF pick the channel
        wr_req_params.vc_sel = eVC_VA;
        wr_req_params.mapVAtoPhysChannel = 1'b1;

        wr_req_params.cl_len = mem_write_req_num_lines;
        wr_req_params.sop = mem_write_req_sop;

        wr_req_params.checkLoadStoreOrder = mem_write_req_check_order;
        wr_req_params.addrIsVirtual = 1'b1;
    end

`ifdef WRFENCE_TEST
    logic maybeEmitWrFence;
    logic [9:0] emitWrFence_cnt;
`endif

    always_ff @(posedge clk)
    begin
        afu_if.c1Tx <=
            cci_mpf_genC1TxWriteReq(
                cci_mpf_c1_genReqHdr(mem_write_req_cached ? eREQ_WRLINE_M : eREQ_WRLINE_I,
                                     mem_write_addr,
                                     t_cci_mdata'(write_req_tag),
                                     wr_req_params),
                mem_write_data,
                mem_write_enable);

`ifdef WRFENCE_TEST
        if (! mem_write_enable && mem_write_rdy && maybeEmitWrFence)
        begin
            afu_if.c1Tx.valid <= 1'b1;
            afu_if.c1Tx.hdr <= t_cci_mpf_c1_ReqMemHdr'(0);
            afu_if.c1Tx.hdr.base.sop <= 1'b1;
            afu_if.c1Tx.hdr.base.cl_len <= eCL_LEN_1;
            afu_if.c1Tx.hdr.base.req_type <= eREQ_WRFENCE;
            afu_if.c1Tx.hdr.base.vc_sel <= eVC_VA;
        end

        maybeEmitWrFence <= (emitWrFence_cnt == 0);
        emitWrFence_cnt <= emitWrFence_cnt + 1;
        if (reset)
        begin
            emitWrFence_cnt <= 0;
        end
`endif
    end

    assign mem_write_rdy = ! afu_if.c1TxAlmFull;
    assign mem_write_ack = cci_c1Rx_isWriteRsp(afu_if.c1Rx);

    always_ff @(posedge clk)
    begin
        if (! reset)
        begin
            assert(mem_read_req_rdy || ! mem_read_req_enable) else
                $fatal("qa_drv_memory: Memory read not ready!");
            assert(mem_write_rdy || ! mem_write_enable) else
                $fatal("qa_drv_memory: Memory write not ready!");
        end
    end

    // Increment mem_req_tag on SOP
    assign write_req_tag_next =
        write_req_tag + t_cci_mdata_platform'(mem_write_enable & mem_write_req_sop);

    // Error checking on read tags, used mostly for checking MPF.
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            // Strange starting value, picked so it isn't aligned with MPF
            // counters in order to look for MPF bugs.
            write_req_tag <= t_cci_mdata_platform'(13);
            read_req_tag <= t_cci_mdata_platform'(27);
            read_rsp_tag <= t_cci_mdata_platform'(27);
        end
        else
        begin
            write_req_tag <= write_req_tag_next;

            if (mem_read_req_enable)
            begin
                read_req_tag <= read_req_tag + 1;
            end

            if (mem_read_rsp_rdy)
            begin
                if (cci_mpf_c0Rx_isEOP(afu_if.c0Rx))
                begin
                    read_rsp_tag <= read_rsp_tag + 1;
                end

                assert(afu_if.c0Rx.hdr.mdata == read_rsp_tag) else
                    $fatal("qa_driver_memory: Incorrect tag (0x%x), expected 0x%x",
                        afu_if.c0Rx.hdr.mdata, read_rsp_tag);
            end
        end
    end


    always_ff @(posedge clk)
    begin
        afu_if.c2Tx <= afu_mmio_rd_rsp;
    end


    // ====================================================================
    //
    //  Connect client requests to the FIU.
    //
    // ====================================================================

    cci_mpf
      #(
        .DFH_MMIO_BASE_ADDR(QA_DRIVER_DFH_SIZE),
        .SORT_READ_RESPONSES(1),
        .ENABLE_VC_MAP(1),
        .ENFORCE_WR_ORDER(1),
        .PRESERVE_WRITE_MDATA(0)
        )
      mpf
       (
        .clk,
        .fiu(fiu),
        .afu(afu_if)
        );

endmodule
