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
`include "cci_test_conf_default.vh"
`include "cci_test_csrs.vh"


//
// Test-independent, generic CSR read and write manager.
//

module cci_test_csrs
  #(
    parameter NEXT_DFH_BYTE_OFFSET = 0
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    // CSR connections to test code.
    test_csrs.csr csrs
    );

    assign afu.reset = fiu.reset;

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end

    // Most connections flow straight through and are, at most, read in this shim.
    assign fiu.c0Tx = afu.c0Tx;
    assign afu.c0TxAlmFull = fiu.c0TxAlmFull;
    assign fiu.c1Tx = afu.c1Tx;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull;

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;

    // Use a small address space for the local CSRs, used after verifying
    // the upper address bits are correct.
    localparam MAX_CSR_ADDR = 32 + NUM_TEST_CSRS;
    typedef logic [$clog2(MAX_CSR_ADDR)-1 : 0] t_afu_csr_addr;

    logic [127:0] afu_id;
    assign afu_id = 128'h438d6c19_ff0c_40da_a43d_1f18bf214d19;

    t_if_cci_c0_Rx c0Rx;
    t_if_cci_c1_Rx c1Rx;

    // Address of incoming MMIO request, truncated to only the bits needed
    // to compute local CSR addresses.
    t_cci_mmioAddr mmio_req_addr;
    assign mmio_req_addr = cci_csr_getAddress(c0Rx);
      
    // TID of incoming MMIO request
    t_ccip_tid mmio_req_tid;
    assign mmio_req_tid = cci_csr_getTid(c0Rx);

    // Is there an incoming MMIO request to an address matching CSRs here?
    logic mmio_req_valid;
    assign mmio_req_valid = (mmio_req_addr < 2 * MAX_CSR_ADDR);

    // CSR read from a valid address?
    logic is_csr_read;
    assign is_csr_read = cci_csr_isRead(c0Rx) && mmio_req_valid;

    // CSR write to a valid address?
    logic is_csr_write;
    assign is_csr_write = cci_csr_isWrite(c0Rx) && mmio_req_valid;

    // The address in local address space (64 bit CSRs)
    t_afu_csr_addr csr_addr;
    assign csr_addr = mmio_req_addr[1 +: $bits(csr_addr)];


    // Counters available in all tests
    t_cci_test_counter ctr_rd_cache_hits;
    t_cci_test_counter ctr_rd_cache_misses;
    t_cci_test_counter ctr_wr_cache_hits;
    t_cci_test_counter ctr_wr_cache_misses;

    t_cci_test_counter ctr_chan_vl0;
    t_cci_test_counter ctr_chan_vh0;
    t_cci_test_counter ctr_chan_vh1;


    always_ff @(posedge clk)
    begin
        c0Rx <= fiu.c0Rx;
        c1Rx <= fiu.c1Rx;
    end


    //
    // CSR reads
    //
    //   In order to be simple this code may fail when a CSR read outside
    //   the space managed here and a CSR read inside the space managed here
    //   are both outstanding.
    //
    t_if_cci_c2_Tx c2Tx;
    always_ff @(posedge clk)
    begin
        fiu.c2Tx <= afu.c2Tx;

        if (c2Tx.mmioRdValid)
        begin
            fiu.c2Tx <= c2Tx;
        end
    end

    always_ff @(posedge clk)
    begin
        c2Tx.mmioRdValid <= is_csr_read;
        c2Tx.hdr.tid <= mmio_req_tid;

        case (csr_addr) inside
          0: // AFU DFH (device feature header)
            begin
                // Construct the DFH (CSR 0)
                t_ccip_dfh afu_dfh;
                afu_dfh = ccip_dfh_defaultDFH();
                afu_dfh.f_type = eFTYP_AFU;
                afu_dfh.nextFeature = NEXT_DFH_BYTE_OFFSET;

                c2Tx.data <= afu_dfh;
            end

          // AFU_ID_L
          1: c2Tx.data <= afu_id[63:0];

          // AFU_ID_H
          2: c2Tx.data <= afu_id[127:64];

          // DFH_RSVD0
          3: c2Tx.data <= t_ccip_mmioData'(0);

          // DFH_RSVD1
          4: c2Tx.data <= t_ccip_mmioData'(0);

          //
          // Standard CSRs available in all tests.
          //

          // AFU frequency (MHz)
          8: c2Tx.data <= `AFU_CLOCK_FREQ;

          // Cache read hits
          9: c2Tx.data <= ctr_rd_cache_hits;

          // Cache read misses
          10: c2Tx.data <= ctr_rd_cache_misses;

          // Cache write hits
          11: c2Tx.data <= ctr_wr_cache_hits;

          // Cache write misses
          12: c2Tx.data <= ctr_wr_cache_misses;

          // Responses on VL0/VH0/VH1
          13: c2Tx.data <= ctr_chan_vl0;
          14: c2Tx.data <= ctr_chan_vh0;
          15: c2Tx.data <= ctr_chan_vh1;

          // FIU state
          16: c2Tx.data <= { 62'(0),
                             fiu.c1TxAlmFull,
                             fiu.c0TxAlmFull };

          // Test CSRs start at 32
          [32 : (32 + NUM_TEST_CSRS - 1)]:
            begin
                c2Tx.data <= csrs.cpu_rd_csrs[csr_addr - 32].data;
            end

           default:
             begin
                c2Tx.data <= t_ccip_mmioData'('x);
             end
        endcase

        if (reset)
        begin
            c2Tx.mmioRdValid <= 1'b0;
        end
    end


    logic [63:0] csr_wr_data;
    assign csr_wr_data = 64'(c0Rx.data);

    //
    // CSR writes
    //
    always_ff @(posedge clk)
    begin
        for (int i = 0; i < NUM_TEST_CSRS; i = i + 1)
        begin
            // Fan out data to all targets
            csrs.cpu_wr_csrs[i].data <= 64'(c0Rx.data);
            csrs.cpu_wr_csrs[i].en <= (t_afu_csr_addr'(i + 32) == csr_addr);
        end

        if (! is_csr_write)
        begin
            for (int i = 0; i < NUM_TEST_CSRS; i = i + 1)
            begin
                csrs.cpu_wr_csrs[i].en <= 1'b0;
            end
        end
    end


    //
    // Track counters
    //

    logic rd_is_vl0;
    logic rd_is_vl0_q;
    assign rd_is_vl0 = ccip_c0Rx_isReadRsp(c0Rx) && (c0Rx.hdr.vc_used == eVC_VL0);
    logic wr_is_vl0;
    logic wr_is_vl0_q;
    assign wr_is_vl0 = ccip_c1Rx_isWriteRsp(c1Rx) && (c1Rx.hdr.vc_used == eVC_VL0);

    logic rd_is_vh0;
    logic rd_is_vh0_q;
    assign rd_is_vh0 = ccip_c0Rx_isReadRsp(c0Rx) && (c0Rx.hdr.vc_used == eVC_VH0);
    logic wr_is_vh0;
    logic wr_is_vh0_q;
    assign wr_is_vh0 = ccip_c1Rx_isWriteRsp(c1Rx) && (c1Rx.hdr.vc_used == eVC_VH0);

    logic rd_is_vh1;
    logic rd_is_vh1_q;
    assign rd_is_vh1 = ccip_c0Rx_isReadRsp(c0Rx) && (c0Rx.hdr.vc_used == eVC_VH1);
    logic wr_is_vh1;
    logic wr_is_vh1_q;
    assign wr_is_vh1 = ccip_c1Rx_isWriteRsp(c1Rx) && (c1Rx.hdr.vc_used == eVC_VH1);

    always_ff @(posedge clk)
    begin
        if (ccip_c0Rx_isReadRsp(c0Rx))
        begin
            if (c0Rx.hdr.hit_miss)
            begin
                ctr_rd_cache_hits <= ctr_rd_cache_hits + t_cci_test_counter'(1);
            end
            else
            begin
                ctr_rd_cache_misses <= ctr_rd_cache_misses + t_cci_test_counter'(1);
            end
        end

        if (ccip_c1Rx_isWriteRsp(c1Rx))
        begin
            if (c1Rx.hdr.hit_miss)
            begin
                ctr_wr_cache_hits <= ctr_wr_cache_hits + t_cci_test_counter'(1);
            end
            else
            begin
                ctr_wr_cache_misses <= ctr_wr_cache_misses + t_cci_test_counter'(1);
            end
        end

        rd_is_vl0_q <= rd_is_vl0;
        wr_is_vl0_q <= wr_is_vl0;
        ctr_chan_vl0 <= ctr_chan_vl0 + t_cci_test_counter'(2'(rd_is_vl0_q) +
                                                           2'(wr_is_vl0_q));

        rd_is_vh0_q <= rd_is_vh0;
        wr_is_vh0_q <= wr_is_vh0;
        ctr_chan_vh0 <= ctr_chan_vh0 + t_cci_test_counter'(2'(rd_is_vh0_q) +
                                                           2'(wr_is_vh0_q));

        rd_is_vh1_q <= rd_is_vh1;
        wr_is_vh1_q <= wr_is_vh1;
        ctr_chan_vh1 <= ctr_chan_vh1 + t_cci_test_counter'(2'(rd_is_vh1_q) +
                                                           2'(wr_is_vh1_q));

        if (reset)
        begin
            ctr_rd_cache_hits <= t_cci_test_counter'(0);
            ctr_rd_cache_misses <= t_cci_test_counter'(0);
            ctr_wr_cache_hits <= t_cci_test_counter'(0);
            ctr_wr_cache_misses <= t_cci_test_counter'(0);
            ctr_chan_vl0 <= t_cci_test_counter'(0);
            ctr_chan_vh0 <= t_cci_test_counter'(0);
            ctr_chan_vh1 <= t_cci_test_counter'(0);

            rd_is_vl0_q <= 1'b0;
            wr_is_vl0_q <= 1'b0;
            rd_is_vh0_q <= 1'b0;
            wr_is_vh0_q <= 1'b0;
            rd_is_vh1_q <= 1'b0;
            wr_is_vh1_q <= 1'b0;
        end
    end


endmodule // cci_test_csrs
