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
`include "qa_driver_csr.vh"


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

    // Incoming signals from the platform
    cci_mpf_if.to_fiu_snoop fiu,

    // Read response output channel
    output t_if_cci_c2_Tx c2Tx,

    // SREG reads.  SREGs are LEAP system registers, accessed via a CSR.
    // The SREG address is written to the CSR and then a CSR read on the
    // same location triggers the request to LEAP.
    output logic sreg_req_rdy,
    input t_sreg sreg_rsp,
    input logic sreg_rsp_enable
    );

`ifdef USE_PLATFORM_CCIS
    // CCI-S has no CSR read.  Use compatibility mode.  Writes to
    // CSR_AFU_MMIO_READ_COMPAT are treated as MMIO read requests.  Responses
    // on c2Tx will be routed to the shared device status memory later
    // in the pipeline.
    parameter CSR_RD_COMPATIBILITY_MODE = 1;
`else
    parameter CSR_RD_COMPATIBILITY_MODE = 0;
`endif

    logic reset_n;
    assign reset_n = fiu.reset_n;


    // Use a small address space for the local CSRs, used after verifying
    // the upper address bits are correct.
    typedef logic [2:0] t_afu_csr_addr;

    logic [127:0] afu_id;
    assign afu_id = AFU_ID;

    logic did_sreg_rsp;
    logic sreg_rsp_enable_q;
    t_sreg sreg_rsp_q;
    t_ccip_tid sreg_tid;

    // Address of incoming MMIO request, truncated to only the bits needed
    // to compute local CSR addresses.
    t_cci_mmioaddr mmio_req_addr;
    assign mmio_req_addr = cci_csr_getAddress(fiu.c0Rx);
      
    // TID of incoming MMIO request
    t_ccip_tid mmio_req_tid;
    assign mmio_req_tid = cci_csr_getTid(fiu.c0Rx);

    // Is there an incoming MMIO request to an address matching CSRs here?
    logic mmio_req_valid;
    assign mmio_req_valid = cci_csr_isRead(fiu.c0Rx) &&
                            (mmio_req_addr <= 8);

    // CCI-S compatibility mode.  See below.
    logic csr_rd_compat_en;
    t_afu_csr_addr csr_rd_compat_addr;

    // Is CSR read enabled (either through MMIO or CCI-S compatibility mode)
    // and is the address in range of the appropriate range?
    logic is_csr_read;
    assign is_csr_read = reset_n && (mmio_req_valid || csr_rd_compat_en);

    // Compute the address to be read, picking either an MMIO or a compatibility
    // mode address.
    t_afu_csr_addr csr_addr;
    assign csr_addr =
        ((CSR_RD_COMPATIBILITY_MODE == 0) ? mmio_req_addr[3:1] : csr_rd_compat_addr);


    always_comb
    begin
        t_ccip_afu_dfh afu_dfh;

        // Normal case -- just pass through read response port to FIU
        c2Tx = t_if_cci_c2_Tx'('x);
        c2Tx.mmioRdValid = 1'b0;
        c2Tx.hdr.tid = mmio_req_tid;

        did_sreg_rsp = 1'b0;

        if (is_csr_read)
        begin
            // Address <= 8 already validated by is_csr_read and the low
            // bit has been dropped.  Addresses are now for 8 byte chunks.
            case (csr_addr)
              0: // AFU DFH (device feature header)
                begin
                    // Construct the DFH (CSR 0)
                    afu_dfh = ccip_dfh_defaultAFU();
                    afu_dfh.next = QA_DRIVER_DFH_SIZE;

                    c2Tx.mmioRdValid = 1'b1;
                    c2Tx.data = afu_dfh;
                end
              1: // AFU_ID_L
                begin
                    c2Tx.mmioRdValid = 1'b1;
                    c2Tx.data = afu_id[63:0];
                end
              2: // AFU_ID_H
                begin
                    c2Tx.mmioRdValid = 1'b1;
                    c2Tx.data = afu_id[127:64];
                end
              3: // DFH_RSVD0
                begin
                    c2Tx.mmioRdValid = 1'b1;
                    c2Tx.data = t_ccip_mmiodata'(0);
                end
              4: // DFH_RSVD1
                begin
                    c2Tx.mmioRdValid = 1'b1;
                    c2Tx.data = t_ccip_mmiodata'(0);
                end
            endcase
        end
        else if (sreg_rsp_enable_q)
        begin
            // Is an SREG response ready to go?  Only one SREG read
            // is allowed outstanding at a time so this can wait for
            // a free slot.
            did_sreg_rsp = 1'b1;

            c2Tx.hdr.tid = sreg_tid;
            c2Tx.mmioRdValid = 1'b1;
            c2Tx.data = sreg_rsp_q;
        end
    end


    generate
        if (CSR_RD_COMPATIBILITY_MODE)
        begin : csr_compat
            //
            // Compatibility mode for CCI-S.  Treat write to
            // CSR_AFU_MMIO_READ_COMPAT as an MMIO read request.
            //
            always_ff @(posedge clk)
            begin
                if (! reset_n)
                begin
                    csr_rd_compat_en <= 1'b0;
                end
                else if (csr_rd_compat_en)
                begin
                    // If reading was permitted then the request fired
                    csr_rd_compat_en <= 1'b0;
                end
                else if (cci_csr_isWrite(fiu.c0Rx) &&
                         csrAddrMatches(fiu.c0Rx, CSR_AFU_MMIO_READ_COMPAT) &&
                         t_cci_mmioaddr'(fiu.c0Rx.data) <= 8)
                begin
                    csr_rd_compat_en <= 1'b1;
                    // Store only the address bits needed for decoding the
                    // CSR address.
                    csr_rd_compat_addr <= fiu.c0Rx.data[3:1];
                end
            end
        end
        else
        begin : csr_native
            // Platforms after CCI-S don't need compatibility mode
            assign csr_rd_compat_en = 1'b0;
        end
    endgenerate


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