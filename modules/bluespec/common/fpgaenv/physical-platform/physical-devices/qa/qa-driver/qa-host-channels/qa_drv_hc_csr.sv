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
`include "cci_csr_if.vh"
`include "qa_drv_hc.vh"

`include "qa-host-channels-params.h"


//
// Consume control/status register writes from the host and broadcast
// CSR state to all consumers through the t_csr.hc_state type.
//

module qa_drv_hc_csr
  #(
    parameter CSR_HC_BASE_ADDR = 0
    )
   (
    input logic clk,
    input logic reset_n,

    // Incoming signals from platform
    input t_if_cci_c0_Rx c0Rx,

    // Parsed CSR messages and state
    output t_qa_drv_hc_csrs csr
    );

    // Check for a CSR address match for a 32-bit object
    function automatic logic csrMatches32(int c);
        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioaddr tgt = t_cci_mmioaddr'((CSR_HC_BASE_ADDR + c) >> 2);

        // Actual address sent in CSR write
        t_cci_mmioaddr addr = cci_csr_getAddress(c0Rx);

        return cci_csr_isWrite(c0Rx) && (addr == tgt);
    endfunction

    // Check for a CSR address match for a 64-bit naturally aligned object
    function automatic logic csrMatches64(int c);
        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioaddr tgt = t_cci_mmioaddr'((CSR_HC_BASE_ADDR + c) >> 2);

        // Actual address sent in CSR write.  64 bit writes may be sent
        // either as a full 64 bit object or as a pair of 32 bit writes,
        // sending the high half before the low half.  Ignore the low
        // address bit to check the match.
        t_cci_mmioaddr addr = cci_csr_getAddress(c0Rx);
        addr[0] = 1'b0;

        return cci_csr_isWrite(c0Rx) && (addr == tgt);
    endfunction


    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            csr.hc_en <= 0;
            csr.hc_en_user_channel <= 0;
        end
        else if (csrMatches32(CSR_HC_EN))
        begin
            csr.hc_en <= c0Rx.data[0];
            csr.hc_en_user_channel <= c0Rx.data[1];
        end
    end

    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            csr.hc_ctrl_frame_valid <= 1'b0;
        end
        else if (csrMatches64(CSR_HC_CTRL_FRAME))
        begin
`ifdef USE_PLATFORM_CCIS
            // Shift in by 32 bit chunks
            csr.hc_ctrl_frame <=
                t_cci_cl_paddr'({ csr.hc_ctrl_frame, c0Rx.data[31:0] });
`else
            csr.hc_ctrl_frame <= t_cci_cl_paddr'(c0Rx.data);
`endif

            // If the low bit of the address is 0 then the register update
            // is complete.  When sent as a pair of 32 bit writes the high
            // half is sent first.
            csr.hc_ctrl_frame_valid <= ~ c0Rx.hdr[0];
        end
    end

    always_ff @(posedge clk)
    begin
        if (csrMatches64(CSR_HC_READ_FRAME))
        begin
`ifdef USE_PLATFORM_CCIS
            // Shift in by chunks
            csr.hc_read_frame <=
                t_cci_cl_paddr'({ csr.hc_read_frame, c0Rx.data[31:0] });
`else
            csr.hc_read_frame <= t_cci_cl_paddr'(c0Rx.data);
`endif
        end
    end

    always_ff @(posedge clk)
    begin
        if (csrMatches64(CSR_HC_WRITE_FRAME))
        begin
`ifdef USE_PLATFORM_CCIS
            // Shift in by chunks
            csr.hc_write_frame <=
                t_cci_cl_paddr'({ csr.hc_write_frame, c0Rx.data[31:0] });
`else
            csr.hc_write_frame <= t_cci_cl_paddr'(c0Rx.data);
`endif
        end
    end


    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            csr.hc_enable_test <= 0;
        end
        else if (csrMatches32(CSR_HC_ENABLE_TEST))
        begin
            csr.hc_enable_test <= c0Rx.data[$bits(t_hc_enable_test)-1 : 0];
        end
        else
        begin
            // Hold request for only one cycle
            csr.hc_enable_test <= 0;
        end
    end

endmodule
