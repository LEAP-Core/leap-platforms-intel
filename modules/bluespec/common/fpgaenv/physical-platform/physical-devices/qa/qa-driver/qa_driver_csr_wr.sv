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

    logic reset;
    assign reset = fiu.reset;

    // Check for a CSR address match
    function automatic logic csrMatches(int c);
        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioAddr tgt = t_cci_mmioAddr'(c >> 2);

        // Actual address sent in CSR write
        t_cci_mmioAddr addr = cci_csr_getAddress(fiu.c0Rx);

        return cci_csr_isWrite(fiu.c0Rx) && (addr == tgt);
    endfunction


    //
    // DSM base address
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            csr.afu_dsm_base_valid <= 1'b0;
            csr.afu_dsm_base[63:58] <= 6'b0;
        end
        else if (csrMatches(CSR_AFU_DSM_BASE))
        begin
            csr.afu_dsm_base <= t_cci_clAddr'(fiu.c0Rx.data[63:6]);
            csr.afu_dsm_base_valid <= 1'b1;
        end
    end


    //
    // The SREG address is specified as a CSR write.  Actually fetching the
    // data will be a later CSR read from the same CSR_AFU_SREG_READ location.
    //
    always_ff @(posedge clk) begin
        if (csrMatches(CSR_AFU_SREG_READ))
        begin
            csr.afu_sreg_addr <= t_sreg_addr'(fiu.c0Rx.data);
        end
    end

endmodule
