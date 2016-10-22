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
`include "cci_test_csrs.vh"


module test_afu
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // CSR connections
    test_csrs.test csrs
    );

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end

    //
    // State machine
    //
    typedef enum logic [1:0]
    {
        STATE_IDLE,
        STATE_RUN,
        STATE_TERMINATE
    }
    t_state;

    t_state state;


    logic c0TxAlmFull;
    logic c1TxAlmFull;

    always_ff @(posedge clk)
    begin
        c0TxAlmFull <= fiu.c0TxAlmFull;
        c1TxAlmFull <= fiu.c1TxAlmFull;

        if (reset)
        begin
            c0TxAlmFull <= 1'b1;
            c1TxAlmFull <= 1'b1;
        end
    end


    // ====================================================================
    //
    //  Test address space.
    //
    // ====================================================================

    // Size of the allocated memory address region
`ifndef CFG_N_MEM_REGION_BITS
  `define CFG_N_MEM_REGION_BITS 24
`endif
    localparam N_MEM_REGION_BITS = `CFG_N_MEM_REGION_BITS;

    typedef logic [N_MEM_REGION_BITS-1 : 0] t_mem_offset;


    // ====================================================================
    //
    //  CSRs
    //
    // ====================================================================

    typedef logic [39 : 0] t_counter;

    t_cci_clAddr dsm;
    t_cci_clAddr rd_mem, wr_mem;
    t_cci_clAddr memMask;

    //
    // Read CSR from host
    //
    t_counter cnt_rd_rsp;
    t_counter cnt_wr_rsp;

    logic [63:0] csr_state;
    always_ff @(posedge clk)
    begin
        csr_state <= { 48'(0),
                       8'(state),
                       6'(0),
                       fiu.c1TxAlmFull,
                       fiu.c0TxAlmFull };
    end

    always_comb
    begin
        // Default
        for (int i = 0; i < NUM_TEST_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end

        // CSR 0 returns random address mapping details so the host can
        // compute the memory size.
        csrs.cpu_rd_csrs[0].data = { 48'(0),
                                     16'(N_MEM_REGION_BITS) };

        csrs.cpu_rd_csrs[1].data = 64'(dsm);
        csrs.cpu_rd_csrs[2].data = 64'(rd_mem);
        csrs.cpu_rd_csrs[3].data = 64'(wr_mem);

        // Number of read responses
        csrs.cpu_rd_csrs[4].data = 64'(cnt_rd_rsp);

        // Number of completed writes
        csrs.cpu_rd_csrs[5].data = 64'(cnt_wr_rsp);

        // Various state
        csrs.cpu_rd_csrs[7].data = csr_state;
    end

    //
    // Incoming configuration
    //
    t_counter cycles_rem;

    t_cci_vc req_vc;
    t_cci_clNum cl_beats;

    typedef logic [15:0] t_stride;
    t_stride stride;
    t_stride offset_base_max;

    logic enable_writes;
    logic enable_reads;

    logic rdline_mode_s;
    logic wrline_mode_m;


    //
    // Consume configuration CSR writes
    //
    always_ff @(posedge clk)
    begin
        if (csrs.cpu_wr_csrs[1].en)
        begin
            dsm <= csrs.cpu_wr_csrs[1].data;
            $display("DSM: 0x%x", csrs.cpu_wr_csrs[1].data);
        end

        if (csrs.cpu_wr_csrs[2].en)
        begin
            rd_mem <= csrs.cpu_wr_csrs[2].data;
            $display("MEM RD: 0x%x", csrs.cpu_wr_csrs[2].data);
        end

        if (csrs.cpu_wr_csrs[3].en)
        begin
            wr_mem <= csrs.cpu_wr_csrs[3].data;
            $display("MEM WR: 0x%x", csrs.cpu_wr_csrs[3].data);
        end

        if (csrs.cpu_wr_csrs[4].en)
        begin
            memMask <= csrs.cpu_wr_csrs[4].data;
            $display("MEM MASK: 0x%x", csrs.cpu_wr_csrs[4].data);
        end
    end

    //
    // Count cycles to run.
    //
    always_ff @(posedge clk)
    begin
        // Normal case: decrement cycle counter
        if (cycles_rem != t_counter'(0))
        begin
            cycles_rem <= cycles_rem - t_counter'(1);
        end

        // Execution cycle count update from the host?
        if (csrs.cpu_wr_csrs[0].en)
        begin
            { cycles_rem,
              stride,
              req_vc,
              cl_beats,
              wrline_mode_m,
              rdline_mode_s,
              enable_writes,
              enable_reads } <= csrs.cpu_wr_csrs[0].data;
        end

        // Offset base max is the largest starting point offset in the buffer
        // when the pointer rotates back to the buffer head.  The starting point
        // is varied on each iteration in order to keep the cache footprint
        // the same independent of stride.
        offset_base_max <=
            (stride == t_stride'(0) ?
             t_stride'(0) :
             // One address below the stride, constrained by the memory area
             (stride - t_stride'(cl_beats) - t_stride'(1)) & memMask);

        if (reset)
        begin
            cycles_rem <= t_counter'(0);
            req_vc <= t_cci_vc'(0);
            cl_beats <= t_cci_clLen'(0);
            wrline_mode_m <= 1'b0;
            rdline_mode_s <= 1'b0;
            enable_writes <= 1'b0;
            enable_reads <= 1'b0;
        end
    end


    logic start_new_run;
    t_cci_clNum wr_beat_num;
    logic wr_beat_last;

    always_ff @(posedge clk)
    begin
        start_new_run <= csrs.cpu_wr_csrs[0].en;

        case (state)
          STATE_IDLE:
            begin
                // New run requested
                if (start_new_run)
                begin
                    state <= STATE_RUN;
                    $display("Starting test...");
                end
            end

          STATE_RUN:
            begin
                // Finished ?
                if (cycles_rem == t_counter'(0))
                begin
                    state <= STATE_TERMINATE;
                    $display("Ending test...");
                end
            end

          default:
            begin
                // Various signalling states terminate when a write is allowed
                if (! c1TxAlmFull && (wr_beat_num == t_cci_clNum'(0)))
                begin
                    state <= STATE_IDLE;
                    $display("Test done.");
                end
            end
        endcase

        if (reset)
        begin
            start_new_run <= 1'b0;
            state <= STATE_IDLE;
        end
    end


    // ====================================================================
    //
    //   Reads
    //
    // ====================================================================

    logic do_read;
    assign do_read = (state == STATE_RUN) && enable_reads && ! c0TxAlmFull;

    t_cci_clAddr rd_offset, rd_offset_next;

    // Shift the base every time the pointer loops back to the head of the
    // buffer in order to hit every line in the region.  This makes the
    // cache footprint the same for each stride.
    t_stride rd_offset_base_next;
    logic rd_offset_base_upd;

    always_ff @(posedge clk)
    begin
        if (rd_offset_base_upd)
        begin
            if (rd_offset_base_next < offset_base_max)
            begin
                rd_offset_base_next <= rd_offset_base_next + t_stride'(1) +
                                       t_stride'(cl_beats);
            end
            else
            begin
                rd_offset_base_next <= t_stride'(0);
            end
        end    

        rd_offset_base_upd <= 1'b0;

        // Next address
        if (do_read)
        begin
            rd_offset <= rd_offset_next;
            rd_offset_next <= rd_offset_next + t_cci_clAddr'(stride);

            if (|(rd_offset_next & ~ memMask))
            begin
                // Overflowed the memory buffer.  Don't just & with memMask
                // since some strides align with the buffer size and some don't,
                // causing some strides to have different cache footprints on
                // different trips through the buffer.  Instead, go back to
                // the buffer head on overflow.
                rd_offset <= t_cci_clAddr'(rd_offset_base_next);
                rd_offset_base_upd <= 1'b1;
                rd_offset_next <= t_cci_clAddr'(rd_offset_base_next) +
                                  t_cci_clAddr'(stride);
            end
        end

        if (reset || start_new_run)
        begin
            rd_offset <= t_cci_clAddr'(0);
            rd_offset_base_next <= t_stride'(0);
            rd_offset_base_upd <= 1'b1;
            rd_offset_next <= t_cci_clAddr'(stride);
        end
    end


    t_cci_mpf_ReqMemHdrParams rd_params;
    t_cci_mpf_c0_ReqMemHdr rd_hdr;

    always_comb
    begin
        rd_params = cci_mpf_defaultReqHdrParams();
        rd_params.vc_sel = req_vc;
        rd_params.mapVAtoPhysChannel = 1'b1;

        rd_hdr = cci_mpf_c0_genReqHdr(
                     (rdline_mode_s ? eREQ_RDLINE_S : eREQ_RDLINE_I),
                     rd_mem + rd_offset,
                     t_cci_mdata'(0),
                     rd_params);

        rd_hdr.base.cl_len = t_cci_clLen'(cl_beats);
    end

    always_ff @(posedge clk)
    begin
        // Request a read when the state is STATE_RUN and the request
        // pipeline has space.
        fiu.c0Tx <= cci_mpf_genC0TxReadReq(rd_hdr, do_read);

        if (reset)
        begin
            fiu.c0Tx.valid <= 1'b0;
        end
    end

    logic c0Rx_is_read_rsp;

    always_ff @(posedge clk)
    begin
        c0Rx_is_read_rsp <= cci_c0Rx_isReadRsp(fiu.c0Rx);
        if (c0Rx_is_read_rsp)
        begin
            cnt_rd_rsp <= cnt_rd_rsp + t_counter'(1);
        end

        if (reset || start_new_run)
        begin
            cnt_rd_rsp <= t_counter'(0);
            c0Rx_is_read_rsp <= 1'b0;
        end
    end

    assign fiu.c2Tx.mmioRdValid = 1'b0;


    // ====================================================================
    //
    //   Writes
    //
    // ====================================================================

    t_cci_clAddr wr_offset, wr_offset_next;

    // Shift the base every time the pointer loops back to the head of the
    // buffer in order to hit every line in the region.  This makes the
    // cache footprint the same for each stride.
    t_stride wr_offset_base_next;
    logic wr_offset_base_upd;

    always_ff @(posedge clk)
    begin
        if (wr_offset_base_upd)
        begin
            if (wr_offset_base_next < offset_base_max)
            begin
                wr_offset_base_next <= wr_offset_base_next + t_stride'(1) +
                                       t_stride'(cl_beats);
            end
            else
            begin
                wr_offset_base_next <= t_stride'(0);
            end
        end    

        wr_offset_base_upd <= 1'b0;

        // Next address
        if ((state == STATE_RUN) && enable_writes && ! c1TxAlmFull &&
            wr_beat_last)
        begin
            wr_offset <= wr_offset_next;
            wr_offset_next <= wr_offset_next + t_cci_clAddr'(stride);

            if (|(wr_offset_next & ~ memMask))
            begin
                // Overflowed the memory buffer.  Don't just & with memMask
                // since some strides align with the buffer size and some don't,
                // causing some strides to have different cache footprints on
                // different trips through the buffer.  Instead, go back to
                // the buffer head on overflow.
                wr_offset <= t_cci_clAddr'(wr_offset_base_next);
                wr_offset_base_upd <= 1'b1;
                wr_offset_next <= t_cci_clAddr'(wr_offset_base_next) +
                                  t_cci_clAddr'(stride);
            end
        end

        if (reset || start_new_run)
        begin
            wr_offset <= t_cci_clAddr'(0);
            wr_offset_base_next <= t_stride'(0);
            wr_offset_base_upd <= 1'b1;
            wr_offset_next <= t_cci_clAddr'(stride);
        end
    end


    t_cci_mpf_ReqMemHdrParams wr_params;
    t_cci_mpf_c1_ReqMemHdr wr_hdr;

    always_comb
    begin
        wr_params = cci_mpf_defaultReqHdrParams();
        wr_params.vc_sel = req_vc;
        wr_params.mapVAtoPhysChannel = 1'b1;

        wr_hdr = cci_mpf_c1_genReqHdr((wrline_mode_m ? eREQ_WRLINE_M : eREQ_WRLINE_I),
                                      wr_mem + wr_offset,
                                      t_cci_mdata'(0),
                                      wr_params);

        // Get the low bits of the address right
        wr_hdr.base.sop = (wr_beat_num == t_cci_clNum'(0));
        wr_hdr.base.cl_len = t_cci_clLen'(cl_beats);
        wr_hdr.base.address[0 +: $bits(t_cci_clNum)] =
            wr_hdr.base.address[0 +: $bits(t_cci_clNum)] | wr_beat_num;
    end


    //
    // Generate write requests
    //
    logic chk_wr_valid_q;

    t_cci_clNum wr_beat_num_next;
    always_comb
    begin
        wr_beat_last = (t_cci_clLen'(wr_beat_num) == cl_beats);

        if (wr_beat_last)
        begin
            wr_beat_num_next = t_cci_clNum'(0);
        end
        else
        begin
            wr_beat_num_next = wr_beat_num + t_cci_clNum'(1);
        end
    end

    always_ff @(posedge clk)
    begin
        chk_wr_valid_q <= 1'b0;
        fiu.c1Tx <= cci_mpf_genC1TxWriteReq(wr_hdr,
                                            t_cci_clData'(0),
                                            1'b0);

        if (wr_beat_num != t_cci_clNum'(0))
        begin
            // Don't stop in the middle of a multi-beat write
            fiu.c1Tx.valid <= 1'b1;
            wr_beat_num <= wr_beat_num_next;
        end
        else if (! c1TxAlmFull)
        begin
            // Normal running state
            if (state == STATE_RUN)
            begin
                fiu.c1Tx.valid <= enable_writes;

                // Update beat number
                if (enable_writes)
                begin
                    wr_beat_num <= wr_beat_num_next;
                end
            end

            // Normal termination: signal done by writing to status memory
            if (state == STATE_TERMINATE)
            begin
                fiu.c1Tx.valid <= 1'b1;
                fiu.c1Tx.hdr.base.address <= dsm;
                fiu.c1Tx.hdr.base.sop <= 1'b1;
                fiu.c1Tx.hdr.base.cl_len <= eCL_LEN_1;
                fiu.c1Tx.hdr.pwrite.isPartialWrite <= 1'b0;
                fiu.c1Tx.data <= t_cci_clData'(1);
            end
        end

        if (reset)
        begin
            fiu.c1Tx.valid <= 1'b0;
            wr_beat_num <= t_cci_clNum'(0);
        end
    end


    logic c1Rx_is_write_rsp;
    t_cci_clNum c1Rx_cl_num;

    always_ff @(posedge clk)
    begin
        c1Rx_is_write_rsp <= cci_c1Rx_isWriteRsp(fiu.c1Rx);
        c1Rx_cl_num <= fiu.c1Rx.hdr.cl_num;

        if (c1Rx_is_write_rsp)
        begin
            // Count beats so multi-line writes get credit for all data
            cnt_wr_rsp <= cnt_wr_rsp + t_counter'(1) + t_counter'(c1Rx_cl_num);
        end

        if (reset || start_new_run)
        begin
            cnt_wr_rsp <= t_counter'(0);
            c1Rx_is_write_rsp <= 1'b0;
        end
    end

endmodule // test_afu