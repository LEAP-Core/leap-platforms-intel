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
import cci_csr_if_pkg::*;
import ccip_feature_list_pkg::*;

//
// Consume control/status register read requests from the host and
// write back the values.
//

module qa_driver_csr_rd
  #(
    // 128 bit AFU ID must be passed in
    AFU_ID = 0
    )
   (
    input logic clk,

    //
    // Signals connecting to QA Platform
    //
    cci_mpf_if.to_fiu fiu,

    //
    // Signals connecting to AFU, the client code
    //
    cci_mpf_if.to_afu afu,

    // SREG reads.  SREGs are LEAP system registers, accessed via a CSR.
    // The SREG address is written to the CSR and then a CSR read on the
    // same location triggers the request to LEAP.
    output logic sreg_req_rdy,
    input t_sreg sreg_rsp,
    input logic sreg_rsp_enable
    );

    logic reset_n;
    assign reset_n = fiu.reset_n;
    assign afu.reset_n = fiu.reset_n;


    //
    // The majority of signals pass straight through.
    //
    assign fiu.c0Tx = afu.c0Tx;
    assign afu.c0TxAlmFull = fiu.c0TxAlmFull;

    assign fiu.c1Tx = afu.c1Tx;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull;

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;

    // Use a small address space for the local CSRs, used after verifying
    // the upper address bits are correct.
    typedef logic [2:0] t_afu_csr_addr;

    // CCI-S compatibility mode.  See below.
    logic csr_rd_compat_en;
    t_afu_csr_addr csr_rd_compat_addr;

    logic [127:0] afu_id;
    assign afu_id = AFU_ID;

    logic did_sreg_rsp;
    logic sreg_rsp_enable_q;
    t_sreg sreg_rsp_q;
    t_ccip_tid sreg_tid;

    // Give priority to existing MMIO responses from the AFU
    logic may_read;
    assign may_read = ! afu.c2Tx.mmioRdValid;

    logic mmio_req_valid;
    t_afu_csr_addr mmio_req_addr;
    t_ccip_tid mmio_req_tid;

    t_afu_csr_addr csr_addr;
    always_comb
    begin
        csr_addr = mmio_req_addr;
        if (csr_rd_compat_en)
        begin
            csr_addr = csr_rd_compat_addr;
        end
    end

    // Is CSR read enabled (either through MMIO or CCI-S compatibility mode)
    // and is the address in range of the appropriate range?
    logic is_csr_read;
    assign is_csr_read = (mmio_req_valid || csr_rd_compat_en);

    always_comb
    begin
        t_ccip_afu_dfh afu_dfh;

        // Construct the DFH (CSR 0)
        afu_dfh = ccip_dfh_defaultAFU();
        afu_dfh.next = QA_DRIVER_DFH_SIZE;

        // Normal case -- just pass through read response port to FIU
        fiu.c2Tx = afu.c2Tx;

        did_sreg_rsp = 1'b0;

        if (may_read && is_csr_read)
        begin
            fiu.c2Tx.hdr.tid = t_ccip_tid'('x);

            // Address <= 8 already validated by is_csr_read and the low
            // bit has been dropped.  Addresses are now for 8 byte chunks.
            case (csr_addr)
              0: // AFU DFH (device feature header)
                begin
                    fiu.c2Tx.hdr.tid = mmio_req_tid;
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = afu_dfh;
                end
              1: // AFU_ID_L
                begin
                    fiu.c2Tx.hdr.tid = mmio_req_tid;
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = afu_id[63:0];
                end
              2: // AFU_ID_H
                begin
                    fiu.c2Tx.hdr.tid = mmio_req_tid;
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = afu_id[127:64];
                end
              3: // DFH_RSVD0
                begin
                    fiu.c2Tx.hdr.tid = mmio_req_tid;
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = t_ccip_mmiodata'(0);
                end
              4: // DFH_RSVD1
                begin
                    fiu.c2Tx.hdr.tid = mmio_req_tid;
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = t_ccip_mmiodata'(0);
                end
            endcase
        end
        else if (may_read && sreg_rsp_enable_q)
        begin
            // Is an SREG response ready to go?  Only one SREG read
            // is allowed outstanding at a time so this can wait for
            // a free slot.
            did_sreg_rsp = 1'b1;

            fiu.c2Tx.hdr.tid = sreg_tid;
            fiu.c2Tx.mmioRdValid = 1'b1;
            fiu.c2Tx.data = sreg_rsp_q;
        end
    end


`ifndef USE_PLATFORM_CCIS

    //
    // This platform has MMIO.  Up to 64 MMIO reads may be in flight.
    // Buffer incoming read requests since the read response port
    // contends with other responders.
    //

    logic mmio_req_enq_en;
    logic mmio_req_not_full;

    // Address of incoming request
    t_cci_mmioaddr mmio_req_addr_in;
    assign mmio_req_addr_in = cci_csr_getAddress(fiu.c0Rx);

    // Store incoming requests only if the address is possibly in range
    assign mmio_req_enq_en = cci_csr_isRead(fiu.c0Rx) &&
                             mmio_req_addr_in <= 8;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(3 + CCIP_TID_WIDTH),
        .N_ENTRIES(64)
        )
      req_fifo
        (
         .clk,
         .reset_n,
         // Store only the MMIO address bits needed for decode
         .enq_data({mmio_req_addr_in[3:1], cci_csr_getTid(fiu.c0Rx)}),
         .enq_en(mmio_req_enq_en),
         .notFull(mmio_req_not_full),
         .almostFull(),
         .first({mmio_req_addr, mmio_req_tid}),
         .deq_en(may_read && mmio_req_valid),
         .notEmpty(mmio_req_valid)
         );

    assign csr_rd_compat_en = 1'b0;

`else

    //
    // Compatibility mode for CCI-S.  Treat write to CSR_AFU_MMIO_READ_COMPAT
    // as an MMIO read request.
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            csr_rd_compat_en <= 1'b0;
        end
        else if (csr_rd_compat_en && may_read)
        begin
            // If reading was permitted then the request fired
            csr_rd_compat_en <= 1'b0;
        end
        else if (cci_csr_isWrite(fiu.c0Rx) &&
                 csrAddrMatches(fiu.c0Rx, CSR_AFU_MMIO_READ_COMPAT) &&
                 t_cci_mmioaddr'(fiu.c0Rx.data) <= 8)
        begin
            csr_rd_compat_en <= 1'b1;
            // Store only the address bits needed for decoding the CSR address
            csr_rd_compat_addr <= fiu.c0Rx.data[3:1];
        end
    end

`endif


    //
    // SREG
    //
    assign sreg_req_rdy = is_csr_read &&
                          (csr_addr == (CSR_AFU_SREG_READ >> 2));

    // Record read request's TID
    always_ff @(posedge clk)
    begin
        if (sreg_req_rdy)
        begin
            sreg_tid <= cci_csr_getTid(fiu.c0Rx);
        end
    end

    // Hold the response until it is emitted
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            sreg_rsp_enable_q <= 1'b0;
        end
        else if (did_sreg_rsp)
        begin
            sreg_rsp_enable_q <= 1'b0;
        end
        else if (sreg_rsp_enable)
        begin
            sreg_rsp_enable_q <= 1'b1;
            sreg_rsp_q <= sreg_rsp;
        end
    end

endmodule // qa_driver_csr_rd
