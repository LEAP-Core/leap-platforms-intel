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
    cci_mpf_if.to_afu afu
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

    // CCI-S compatibility mode.  See below.
    logic csr_rd_compat_en;
    logic did_csr_rd_compat;
    t_cci_mmioaddr csr_rd_compat_addr;

    logic [127:0] afu_id;
    assign afu_id = AFU_ID;

    always_comb
    begin
        t_cci_mmioaddr addr;
        did_csr_rd_compat = 1'b0;

        // Normal case -- just pass through read response port to FIU
        fiu.c2Tx = t_if_cci_c2_Tx'(0);

        if (cci_csr_isRead(fiu.c0Rx) || csr_rd_compat_en)
        begin
            addr = cci_csr_getAddress(fiu.c0Rx);
            if (csr_rd_compat_en)
            begin
                addr = csr_rd_compat_addr;
                did_csr_rd_compat = 1'b1;
            end

            case (addr)
              0: // AFU DFH (device feature header)
                begin
                    fiu.c2Tx.hdr.tid = cci_csr_getTid(fiu.c0Rx);
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = ccip_dfh_defaultAFU();
                end
              2: // AFU_ID_L
                begin
                    fiu.c2Tx.hdr.tid = cci_csr_getTid(fiu.c0Rx);
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = afu_id[63:0];
                end
              4: // AFU_ID_H
                begin
                    fiu.c2Tx.hdr.tid = cci_csr_getTid(fiu.c0Rx);
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = afu_id[127:64];
                end
              6: // DFH_RSVD0
                begin
                    fiu.c2Tx.hdr.tid = cci_csr_getTid(fiu.c0Rx);
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = t_ccip_mmiodata'(0);
                end
              8: // DFH_RSVD1
                begin
                    fiu.c2Tx.hdr.tid = cci_csr_getTid(fiu.c0Rx);
                    fiu.c2Tx.mmioRdValid = 1'b1;
                    fiu.c2Tx.data = t_ccip_mmiodata'(0);
                end
            endcase
        end
    end

`ifndef USE_PLATFORM_CCIS

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
        else if (did_csr_rd_compat)
        begin
            csr_rd_compat_en <= 1'b0;
        end
        else if (cci_csr_isWrite(fiu.c0Rx) &&
                 csrAddrMatches(fiu.c0Rx, CSR_AFU_MMIO_READ_COMPAT))
        begin
            csr_rd_compat_en <= 1'b1;
            csr_rd_compat_addr <= t_cci_mmioaddr'(fiu.c0Rx.data);
        end
    end

`endif

endmodule // qa_driver_csr_rd

