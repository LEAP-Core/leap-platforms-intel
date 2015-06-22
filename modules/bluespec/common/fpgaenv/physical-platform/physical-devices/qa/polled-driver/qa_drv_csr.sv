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
// Consume control/status register writes from the host and broadcast
// CSR state to all consumers through the t_CSR_AFU_STATE type.
//

`include "qa.vh"

module qa_drv_csr
    (input logic clk,
     input logic resetb,
     input rx_c0_t rx0,

     output t_CSR_AFU_STATE csr
    );

    always_comb
    begin
        if (rx0.cfgvalid)
            $display("SETTING CONFIG 0x%h 0x%h", {rx0.header[13:0], 2'b0}, rx0.data[31:0]);
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_DSM_BASEL)) begin
            csr.afu_dsm_base[31:0] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
            csr.afu_dsm_base_valid <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_DSM_BASEL)) begin
            csr.afu_dsm_base_valid <= 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_DSM_BASEH)) begin
            csr.afu_dsm_base[63:32] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_CNTXT_BASEL)) begin
            csr.afu_cntxt_base[31:0] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
           csr.afu_cntxt_base_valid <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_CNTXT_BASEL)) begin
            csr.afu_cntxt_base_valid <= 1;
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_CNTXT_BASEH)) begin
            csr.afu_cntxt_base[63:32] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
            csr.afu_en <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_EN)) begin
            csr.afu_en <= rx0.data[0];
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
            csr.afu_trigger_debug.idx <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_TRIGGER_DEBUG)) begin
            csr.afu_trigger_debug <= rx0.data[$bits(t_AFU_DEBUG_REQ)-1 : 0];
        end
        else begin
            // Hold request for only one cycle.  Only the idx is cleared.
            // subIdx is left alone so it can be used to index storage until
            // the next request is received.
            csr.afu_trigger_debug.idx <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
            csr.afu_enable_test <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_ENABLE_TEST)) begin
            csr.afu_enable_test <= rx0.data[$bits(t_AFU_ENABLE_TEST)-1 : 0];
        end
        else begin
            // Hold request for only one cycle
            csr.afu_enable_test <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (~resetb) begin
            csr.afu_sreg_req.enable <= 0;
        end
        else if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_SREG_READ)) begin
            csr.afu_sreg_req.enable <= 1;
            csr.afu_sreg_req.addr <= rx0.data[$bits(t_SREG_ADDR)-1 : 0];
        end
        else begin
            // Hold request for only one cycle
            csr.afu_sreg_req.enable <= 0;
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_READ_FRAME_BASEL)) begin
            csr.afu_read_frame[31:0] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_READ_FRAME_BASEH)) begin
           csr.afu_read_frame[63:32] <= rx0.data[31:0];

        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_WRITE_FRAME_BASEL)) begin
            csr.afu_write_frame[31:0] <= rx0.data[31:0];
        end
    end

    always_ff @(posedge clk) begin
        if (rx0.cfgvalid && csr_addr_matches(rx0.header, CSR_AFU_WRITE_FRAME_BASEH)) begin
            csr.afu_write_frame[63:32] <= rx0.data[31:0];
        end
    end
endmodule