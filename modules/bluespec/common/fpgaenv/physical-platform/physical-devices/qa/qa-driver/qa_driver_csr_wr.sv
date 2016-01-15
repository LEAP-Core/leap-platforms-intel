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

`include "cci_mpf_if.vh"
`include "qa_driver_csr.vh"


//
// Consume control/status register writes from the host and broadcast
// CSR state to all consumers through the t_csr_afu_state type.
//

module qa_driver_csr_wr
   (
    input logic clk,

    // Incoming signals from platform
    cci_mpf_if.to_fiu_snoop fiu,

    // Parsed CSR messages and state
    output t_csr_afu_state csr
    );

    logic reset_n;
    assign reset_n = fiu.reset_n;

    // Check for a CSR address match for a 32-bit object
    function automatic logic csrMatches32(int c);
        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioaddr tgt = t_cci_mmioaddr'(c >> 2);

        // Actual address sent in CSR write
        t_cci_mmioaddr addr = cci_csr_getAddress(fiu.c0Rx);

        return cci_csr_isWrite(fiu.c0Rx) && (addr == tgt);
    endfunction

    // Check for a CSR address match for a 64-bit naturally aligned object
    function automatic logic csrMatches64(int c);
        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioaddr tgt = t_cci_mmioaddr'(c >> 2);

        // Actual address sent in CSR write.  64 bit writes may be sent
        // either as a full 64 bit object or as a pair of 32 bit writes,
        // sending the high half before the low half.  Ignore the low
        // address bit to check the match.
        t_cci_mmioaddr addr = cci_csr_getAddress(fiu.c0Rx);
        addr[0] = 1'b0;

        return cci_csr_isWrite(fiu.c0Rx) && (addr == tgt);
    endfunction


    //
    // DSM base address
    //
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            csr.afu_dsm_base_valid <= 0;
            csr.afu_dsm_base[63:58] <= 6'b0;
        end
        else if (csrMatches64(CSR_AFU_DSM_BASE))
        begin
`ifdef USE_PLATFORM_CCIS
            // 32 bit chunks
            if (fiu.c0Rx.hdr[0] == 1)
            begin
                csr.afu_dsm_base[57:26] <= fiu.c0Rx.data[31:0];
            end
            else
            begin
                csr.afu_dsm_base[25:0] <= fiu.c0Rx.data[31:6];
            end
`else
            // Single chunk
            csr.afu_dsm_base <= t_cci_cl_paddr'(fiu.c0Rx.data[63:6]);
`endif

            // If the low bit of the address is 0 then the register update
            // is complete.  When sent as a pair of 32 bit writes the high
            // half is sent first.
            csr.afu_dsm_base_valid <= ~ fiu.c0Rx.hdr[0];
        end
    end


    //
    // The SREG address is specified as a CSR write.  Actually fetching the
    // data will be a later CSR read from the same CSR_AFU_SREG_READ location.
    //
    always_ff @(posedge clk) begin
        if (csrMatches32(CSR_AFU_SREG_READ))
        begin
            csr.afu_sreg_addr <= t_sreg_addr'(fiu.c0Rx.data);
        end
    end

endmodule
