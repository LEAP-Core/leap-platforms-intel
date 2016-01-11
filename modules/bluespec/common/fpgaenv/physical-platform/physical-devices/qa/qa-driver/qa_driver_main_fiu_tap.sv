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
import qa_driver_csr_types::*;


module qa_driver_main_fiu_tap
  #(
    //
    // Pass in the AFU ID.  This module writes AFU ID to the base of the
    // device status memory for the CCI-S protocol.
    //
    AFU_ID = 0,

    //
    // When the driver injects write requests they will be tagged with this
    // value in Mdata. Write responses matching the tag are dropped here.
    //
    QA_DRIVER_WRITE_TAG = 0
    )
   (
    input  logic clk,

    // Connection toward the platform
    cci_mpf_if.to_fiu fiu,

    // Connection toward the rest of the driver and then user code
    cci_mpf_if.to_afu afu,

    // CSR monitoring
    input t_csr_afu_state csr,

    // LEAP status registers to be written to host
    input t_sreg sreg_rsp,
    input logic  sreg_rsp_enable
    );

    logic reset_n;
    assign reset_n = fiu.reset_n;
    assign afu.reset_n = fiu.reset_n;

    logic did_afu_id_write;

    //
    // Extra logic for CSR read from host addition to CCI-S.  This is a
    // compatibility extension to CCI-S to emulate the MMIO read available
    // in CCI-P.  This compatibility mode maps MMIO read responses to
    // DSM line 1 writes.
    // 
    // Note: in this compatibility mode only one CSR read may be in flight
    // at a time.
    //
    t_if_cci_c2_Tx mmio_read_rsp_q;
    logic did_mmio_read_rsp;

    t_sreg sreg_rsp_q;
    logic sreg_rsp_enable_q;
    logic did_sreg_writeback;

    always_comb
    begin
        // Request channels to host
        fiu.c0Tx = afu.c0Tx;
        afu.c0TxAlmFull = fiu.c0TxAlmFull;

        fiu.c1Tx = afu.c1Tx;
        afu.c1TxAlmFull = fiu.c1TxAlmFull;

        fiu.c2Tx = afu.c2Tx;

        did_mmio_read_rsp = 1'b0;
        did_sreg_writeback = 1'b0;

        //
        // Inject memory writes for special cases:
        //

        // Give priority to AFU activity.  Special cases considered only when
        // memory writes are permitted and there is no traffic already generated
        // this cycle by the AFU.
        if (! fiu.c1TxAlmFull && ! cci_mpf_c1TxIsValid(afu.c1Tx))
        begin
            // Need to set AFU_ID in DSM?  This can always be done since
            // the AFU won't be active until the DSM is initialized.
            if (! did_afu_id_write && csr.afu_dsm_base_valid)
            begin
                fiu.c1Tx.wrValid = 1'b1;
                fiu.c1Tx.hdr = cci_mpf_genReqHdr(eREQ_WRLINE_I,
                                                 csr.afu_dsm_base,
                                                 t_cci_mdata'(QA_DRIVER_WRITE_TAG),
                                                 cci_mpf_defaultReqHdrParams(0));
                fiu.c1Tx.data[127:0] = AFU_ID;
            end
`ifdef USE_PLATFORM_CCIS
            else if (mmio_read_rsp_q.mmioRdValid)
            begin
                // Map MMIO read response to a memory write. A software-side
                // CSR read compatibility function expects it there.
                did_mmio_read_rsp = 1'b1;

                // Write to DSM line 1.  The value goes in the low 64 bits.
                // Use the bit 64 to note that the write happend.
                fiu.c1Tx.wrValid = 1'b1;
                fiu.c1Tx.hdr = cci_mpf_genReqHdr(eREQ_WRLINE_I,
                                                 csr.afu_dsm_base | 1'b1,
                                                 t_cci_mdata'(QA_DRIVER_WRITE_TAG),
                                                 cci_mpf_defaultReqHdrParams(0));
                fiu.c1Tx.data[CCIP_MMIODATA_WIDTH-1:0] = mmio_read_rsp_q.data;
                fiu.c1Tx.data[64] = 1'b1;
            end
`endif
            else if (sreg_rsp_enable_q)
            begin
                // There is an SREG response ready, the output queue is data
                // ready and there is no traffic coming from the AFU.
                did_sreg_writeback = 1'b1;

                // Write to DSM line 1.  The value goes in the low 64 bits.
                // Use the bit 64 to note that the write happend.
                fiu.c1Tx.wrValid = 1'b1;
                fiu.c1Tx.hdr = cci_mpf_genReqHdr(eREQ_WRLINE_I,
                                                 csr.afu_dsm_base | 1'b1,
                                                 t_cci_mdata'(QA_DRIVER_WRITE_TAG),
                                                 cci_mpf_defaultReqHdrParams(0));
                fiu.c1Tx.data[63:0] = sreg_rsp_q;
                fiu.c1Tx.data[64] = 1'b1;
            end
        end


        // Response channels from host.  
        afu.c0Rx = fiu.c0Rx;
        afu.c1Rx = fiu.c1Rx;

        // Drop the driver write responses
        if (fiu.c0Rx.wrValid &&
            (fiu.c0Rx.hdr.mdata == t_cci_mdata'(QA_DRIVER_WRITE_TAG)))
        begin
            afu.c0Rx.wrValid = 1'b0;
        end

        if (fiu.c1Rx.wrValid &&
            (fiu.c1Rx.hdr.mdata == t_cci_mdata'(QA_DRIVER_WRITE_TAG)))
        begin
            afu.c1Rx.wrValid = 1'b0;
        end
    end


    //
    // Track writing AFU_ID to DSM line 0.
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            did_afu_id_write <= 1'b0;
        end
        else
        begin
            // AFU_ID will be written at the first opportunity
            did_afu_id_write <= csr.afu_dsm_base_valid;
        end
    end


    //
    // Track compatibility-mode mapping CSR read responses to DSM writes
    // in CCI-S.  Only one CSR read is allowed to be outstanding at a time.
    //
`ifdef USE_PLATFORM_CCIS
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            mmio_read_rsp_q.mmioRdValid <= 1'b0;
        end
        else if (did_mmio_read_rsp)
        begin
            mmio_read_rsp_q.mmioRdValid <= 1'b0;
        end
        else if (! mmio_read_rsp_q.mmioRdValid)
        begin
            mmio_read_rsp_q <= fiu.c2Tx;
        end
    end
`else
    // Compatibility mode not required
    assign mmio_read_rsp_q.mmioRdValid = 1'b0;
`endif


    //
    // Track writing SREG response to DSM line 1.  Only one SREG read
    // is allowed to be outstanding at a time.
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            sreg_rsp_enable_q <= 1'b0;
        end
        else if (did_sreg_writeback)
        begin
            sreg_rsp_enable_q <= 1'b0;
        end
        else if (! sreg_rsp_enable_q)
        begin
            sreg_rsp_enable_q <= sreg_rsp_enable;
            sreg_rsp_q <= sreg_rsp;
        end
    end

endmodule // qa_driver_main_fiu_tap
