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

    logic chk_rdy;


    //
    // State machine
    //
    typedef enum
    {
        STATE_IDLE,
        STATE_RUN,
        STATE_TERMINATE,
        STATE_ERROR
    }
    t_state;

    t_state state;
    logic raise_error;

    logic chk_ram_rdy;
    logic chk_fifo_full;


    // ====================================================================
    //
    // Random address generation function maps N_RAND_ADDR_BITS into a
    // line address.  Some input bits wind up in low address bits and some
    // wind up in higher bits that are on different pages.  This lets us
    // use a small enough working address space that it can be mapped to
    // block RAM for verification while also testing various MPF features.
    //
    // ====================================================================

    typedef logic [31:0] t_random;

    // Size of the allocated memory address region
    localparam N_MEM_REGION_BITS = 18;

    // Size of the checker region.  If this is smaller than N_MEM_REGION_BITS
    // then a subset of references are checked.
    localparam N_CHECKED_ADDR_BITS = 14;
    typedef logic [N_CHECKED_ADDR_BITS-1 : 0] t_checked_addr_idx;

    // The checked address space is a mapping from the larger memory region,
    // taking mostly low address bits from the memory region but including
    // a few high bits so that multiple virtual pages are checked.  References
    // are checked only when the unmapped middle address bits are zero.

    localparam N_CHECKED_LOW_ADDR_BITS = 9;

    typedef struct packed {
        logic [N_CHECKED_ADDR_BITS-N_CHECKED_LOW_ADDR_BITS-1 : 0] checked_high;
        logic [N_MEM_REGION_BITS-N_CHECKED_ADDR_BITS-1 : 0] unchecked_middle;
        logic [N_CHECKED_LOW_ADDR_BITS-1 : 0] checked_low;
    }
    t_mapped_addr_bits;


    // Random address type from a 32 bit LFSR
    function automatic t_mapped_addr_bits randAddrInFromLFSR(t_random r);
        return t_mapped_addr_bits'(r);
    endfunction

    // Random cache line address from a mapped address
    function automatic t_cci_clAddr randAddr(t_cci_clAddr base,
                                             t_mapped_addr_bits m);
        return base + t_cci_clAddr'(m);
    endfunction

    // Is an index checked?  Only a subset of references have a corresponding
    // block RAM check value.
    function automatic logic addrIsChecked(t_mapped_addr_bits m);
        // Check only if the unchecked middle bits are all zero.  Any
        // single state of the unchecked middle bits would work.
        return (|(m.unchecked_middle) == 1'b0);
    endfunction

    // Map full random address space to the checked space
    function automatic t_checked_addr_idx checkedAddr(t_mapped_addr_bits m);
        return {m.checked_high, m.checked_low};
    endfunction


    // ====================================================================
    //
    //  CSRs
    //
    // ====================================================================

    typedef logic [39 : 0] t_counter;

    t_cci_clAddr dsm;
    t_cci_clAddr mem;
    t_cci_clAddr memMask;

    //
    // Read CSR from host
    //
    t_counter cnt_rd_rsp;
    t_counter cnt_wr_rsp;
    t_counter cnt_checked_rd;

    always_comb
    begin
        // Default
        for (int i = 0; i < NUM_TEST_CSRS; i = i + 1)
        begin
            csrs.cpu_rd_csrs[i].data = 64'(0);
        end

        // CSR 0 returns random address mapping details so the host can
        // compute the memory size.
        csrs.cpu_rd_csrs[0].data = { 32'(0),
                                     16'(N_CHECKED_ADDR_BITS),
                                     16'(N_MEM_REGION_BITS) };

        csrs.cpu_rd_csrs[1].data = 64'(dsm);
        csrs.cpu_rd_csrs[2].data = 64'(mem);

        // Number of checked read responses
        csrs.cpu_rd_csrs[4].data = 64'(cnt_rd_rsp);

        // Number of completed writes
        csrs.cpu_rd_csrs[5].data = 64'(cnt_wr_rsp);

        // Number of checked reads
        csrs.cpu_rd_csrs[6].data = 64'(cnt_checked_rd);

        // Various state
        csrs.cpu_rd_csrs[7].data = { 48'(0),
                                     8'(state),
                                     3'(0),
                                     chk_ram_rdy,
                                     chk_fifo_full,
                                     raise_error,
                                     fiu.c1TxAlmFull,
                                     fiu.c0TxAlmFull };
    end

    //
    // Incoming configuration
    //
    t_counter cycles_rem;
    logic enable_writes;
    logic enable_reads;

    logic enable_wro;
    logic enable_checker;
    logic enable_rw_conflicts;

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
            mem <= csrs.cpu_wr_csrs[2].data;
            $display("MEM: 0x%x", csrs.cpu_wr_csrs[2].data);
        end

        if (csrs.cpu_wr_csrs[3].en)
        begin
            memMask <= csrs.cpu_wr_csrs[3].data;
            $display("MEM MASK: 0x%x", csrs.cpu_wr_csrs[3].data);
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
              enable_rw_conflicts,
              enable_checker,
              enable_wro,
              enable_writes,
              enable_reads } <= csrs.cpu_wr_csrs[0].data;
        end

        if (reset)
        begin
            cycles_rem <= t_counter'(0);
            enable_writes <= 1'b0;
            enable_reads <= 1'b0;
            enable_wro <= 1'b0;
            enable_checker <= 1'b0;
            enable_rw_conflicts <= 1'b0;
        end
    end


    logic start_new_run;
    assign start_new_run = csrs.cpu_wr_csrs[0].en;

    always_ff @(posedge clk)
    begin
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

                if (raise_error)
                begin
                    state <= STATE_ERROR;
                end
            end

          default:
            begin
                // Various signalling states terminate when a write is allowed
                if (! fiu.c1TxAlmFull)
                begin
                    state <= STATE_IDLE;
                    $display("Test done.");
                end
            end
        endcase

        if (reset)
        begin
            state <= STATE_IDLE;
        end
    end


    // ====================================================================
    //
    //   Reads
    //
    // ====================================================================

    t_cci_mpf_ReqMemHdrParams rd_params;
    always_comb
    begin
        rd_params = cci_mpf_defaultReqHdrParams();
        rd_params.checkLoadStoreOrder = enable_wro;
        rd_params.vc_sel = eVC_VA;
        rd_params.mapVAtoPhysChannel = 1'b1;
    end

    //
    // Random address
    //
    t_random rd_lfsr_val;
    cci_mpf_prim_lfsr32
      #(
        .INITIAL_VALUE(32'h2721)
        )
      rd_lfsr
       (
        .clk,
        .reset,
        .en(1'b1),
        .value(rd_lfsr_val)
        );

    t_mapped_addr_bits rd_addr_rand_idx;
    always_comb
    begin
        rd_addr_rand_idx = randAddrInFromLFSR(rd_lfsr_val);

        // If read/write conflicts aren't allowed then force an address bit
        // to zero.  The corresponding bit for writes will be forced to one.
        if (! enable_rw_conflicts)
        begin
            rd_addr_rand_idx.checked_low[0] = 1'b0;
        end
    end

    t_cci_clAddr rd_rand_addr;
    logic rd_addr_is_checked;
    t_checked_addr_idx rd_addr_chk_idx;
    t_checked_addr_idx rd_addr_chk_idx_q;

    // Map the random address index to the address space
    always_ff @(posedge clk)
    begin
        rd_rand_addr <= randAddr(mem, rd_addr_rand_idx);

        rd_addr_is_checked <= addrIsChecked(rd_addr_rand_idx);
        rd_addr_chk_idx <= checkedAddr(rd_addr_rand_idx);
        rd_addr_chk_idx_q <= rd_addr_chk_idx;
    end


    t_cci_mpf_c0_ReqMemHdr rd_hdr;
    always_comb
    begin
        rd_hdr = cci_mpf_c0_genReqHdr(
                     eREQ_RDLINE_S,
                     rd_rand_addr,
                     // Indicate in mdata whether requested address is checked
                     t_cci_mdata'(rd_addr_is_checked ? 1'b1 : 1'b0),
                     rd_params);
    end

    always_ff @(posedge clk)
    begin
        // Request a read when the state is STATE_RUN and the request
        // pipeline has space.
        fiu.c0Tx <=
            cci_mpf_genC0TxReadReq(rd_hdr,
                                   (state == STATE_RUN) &&
                                   enable_reads &&
                                   chk_rdy &&
                                   ! fiu.c0TxAlmFull);

        if (reset)
        begin
            fiu.c0Tx.valid <= 1'b0;
        end
    end

    always_ff @(posedge clk)
    begin
        if (cci_c0Rx_isReadRsp(fiu.c0Rx))
        begin
            cnt_rd_rsp <= cnt_rd_rsp + t_counter'(1);
        end

        if (reset || start_new_run)
        begin
            cnt_rd_rsp <= t_counter'(0);
        end
    end

    assign fiu.c2Tx.mmioRdValid = 1'b0;


    // ====================================================================
    //
    //   Writes
    //
    // ====================================================================

    t_cci_mpf_ReqMemHdrParams wr_params;
    always_comb
    begin
        wr_params = cci_mpf_defaultReqHdrParams();
        wr_params.checkLoadStoreOrder = enable_wro;
        wr_params.vc_sel = eVC_VA;
        wr_params.mapVAtoPhysChannel = 1'b1;
    end

    //
    // Random address
    //
    t_random wr_lfsr_val;
    cci_mpf_prim_lfsr32
      #(
        .INITIAL_VALUE(32'h8520)
        )
      wr_lfsr
       (
        .clk,
        .reset,
        .en(1'b1),
        .value(wr_lfsr_val)
        );

    t_mapped_addr_bits wr_addr_rand_idx;
    always_comb
    begin
        wr_addr_rand_idx = randAddrInFromLFSR(wr_lfsr_val);

        // If read/write conflicts aren't allowed then force an address bit
        // to one.  The corresponding bit for reads will be forced to zero.
        if (! enable_rw_conflicts)
        begin
            wr_addr_rand_idx.checked_low[0] = 1'b1;
        end
    end

    t_cci_clAddr wr_rand_addr;
    logic wr_addr_is_checked;
    t_checked_addr_idx wr_addr_chk_idx;
    t_checked_addr_idx wr_addr_chk_idx_q;

    // Map the random address index to the address space
    always_ff @(posedge clk)
    begin
        wr_rand_addr <= randAddr(mem, wr_addr_rand_idx);

        wr_addr_is_checked <= addrIsChecked(wr_addr_rand_idx);
        wr_addr_chk_idx <= checkedAddr(wr_addr_rand_idx);
        wr_addr_chk_idx_q <= wr_addr_chk_idx;
    end


    t_cci_mpf_c1_ReqMemHdr wr_hdr;
    always_comb
    begin
        wr_hdr = cci_mpf_c1_genReqHdr(eREQ_WRLINE_M,
                                      wr_rand_addr,
                                      t_cci_mdata'(0),
                                      wr_params);
    end

    //
    // Random data
    //
    logic [(CCI_CLDATA_WIDTH / 32)-1 : 0][31:0] wr_rand_data;
    genvar r;
    generate
        for (r = 0; r < CCI_CLDATA_WIDTH / 32; r = r + 1)
        begin : d
            cci_mpf_prim_lfsr32
              #(
                .INITIAL_VALUE(32'(r+1))
                )
              wr_lfsr
               (
                .clk,
                .reset,
                .en(1'b1),
                .value(wr_rand_data[r])
                );
        end
    endgenerate

    logic chk_wr_valid_q;

    always_ff @(posedge clk)
    begin
        chk_wr_valid_q <= 1'b0;
        fiu.c1Tx <= cci_mpf_genC1TxWriteReq(wr_hdr,
                                            t_cci_clData'(wr_rand_data),
                                            1'b0);

        if (! fiu.c1TxAlmFull)
        begin
            // Normal running state
            if (state == STATE_RUN)
            begin
                fiu.c1Tx.valid <= chk_rdy && enable_writes;
                chk_wr_valid_q <= chk_rdy && enable_writes && wr_addr_is_checked;
            end

            // Normal termination: signal done by writing to status memory
            if (state == STATE_TERMINATE)
            begin
                fiu.c1Tx.valid <= 1'b1;
                fiu.c1Tx.hdr.base.address <= dsm;
                fiu.c1Tx.data <= t_cci_clData'(1);
            end

            // Error termination: signal error in status memory
            if (state == STATE_ERROR)
            begin
                fiu.c1Tx.valid <= 1'b1;
                fiu.c1Tx.hdr.base.address <= dsm;
                fiu.c1Tx.data <= t_cci_clData'(2);
            end
        end

        if (reset)
        begin
            fiu.c1Tx.valid <= 1'b0;
        end
    end

    always_ff @(posedge clk)
    begin
        if (cci_c1Rx_isWriteRsp(fiu.c1Rx))
        begin
            cnt_wr_rsp <= cnt_wr_rsp + t_counter'(1);
        end

        if (reset || start_new_run)
        begin
            cnt_wr_rsp <= t_counter'(0);
        end
    end


    // ====================================================================
    //
    //   Checker
    //
    // ====================================================================

    // Map one line to a tag
    typedef logic [31:0] t_mem_tag;
    typedef logic [($bits(t_mem_tag) / 8) - 1 : 0] t_mem_tag_mask;

    // Pick some bytes that will be compared.  The rest will be thrown away.
    // Entire bytes are chosen so we can test byte-masked writes.
    function automatic t_mem_tag lineToTag(t_cci_clData v);
        return { v[(8 * 59) +: 8], v[(8 * 35) +: 8], 
                 v[(8 * 13) +: 8], v[(8 * 0) +: 8] };
    endfunction

    //
    // Block RAM holding tags representing memory state
    //
    t_mem_tag rd_chk_data;

    always_ff @(posedge clk)
    begin
        chk_rdy <= chk_ram_rdy && ! chk_fifo_full;
        if (reset)
        begin
            chk_rdy <= 1'b0;
        end
    end

    cci_mpf_prim_ram_dualport_byteena_init
      #(
        .N_ENTRIES(1 << N_CHECKED_ADDR_BITS),
        .N_DATA_BITS($bits(t_mem_tag)),
        .N_OUTPUT_REG_STAGES(2),
        .READ_DURING_WRITE_MODE_MIXED_PORTS("OLD_DATA")
        )
      chk_ram
       (
        .reset,
        .rdy(chk_ram_rdy),

        // Update RAM with written data
        .clk0(clk),
        .addr0(wr_addr_chk_idx_q),
        .wen0(chk_wr_valid_q),
        .byteena0(~ t_mem_tag_mask'(0)),
        .wdata0(lineToTag(fiu.c1Tx.data)),
        .rdata0(),

        // Reads match CCI read requests
        .clk1(clk),
        .addr1(rd_addr_chk_idx_q),
        .wen1(1'b0),
        .byteena1(),
        .wdata1(),
        .rdata1(rd_chk_data)
        );

    // Forward block RAM reads to a FIFO.  The block RAM reads will be matched
    // with CCI read responses.
    logic chk_rd_q;
    logic chk_rd_qq;
    logic chk_rd_qqq;

    t_cci_clAddr chk_rd_addr_q;
    t_cci_clAddr chk_rd_addr_qq;
    t_cci_clAddr chk_rd_addr_qqq;

    always_ff @(posedge clk)
    begin
        // mdata[0] indicates whether the read is checked
        chk_rd_q <= fiu.c0Tx.valid && fiu.c0Tx.hdr.base.mdata[0];
        chk_rd_qq <= chk_rd_q;
        chk_rd_qqq <= chk_rd_qq;

        chk_rd_addr_q <= fiu.c0Tx.hdr.base.address;
        chk_rd_addr_qq <= chk_rd_addr_q;
        chk_rd_addr_qqq <= chk_rd_addr_qq;

        if (reset)
        begin
            chk_rd_q <= 1'b0;
            chk_rd_qq <= 1'b0;
            chk_rd_qqq <= 1'b0;
        end
    end

    t_mem_tag chk_first;
    t_cci_clAddr chk_first_addr;

    //
    // Much of the data flowing through the FIFOs is consumed only by
    // $display() and will be dropped by HW synthesis.
    //

    logic chk_notEmpty;
    logic rsp_notEmpty;

    logic fifo_deq;
    assign fifo_deq = chk_notEmpty && rsp_notEmpty;

    cci_mpf_prim_fifo_bram
      #(
        .N_DATA_BITS($bits(t_mem_tag) + $bits(t_cci_clAddr)),
        .N_ENTRIES(1024),
        .THRESHOLD(8)
        )
      chk_fifo
       (
        .clk,
        .reset,

        .enq_data({rd_chk_data, chk_rd_addr_qqq}),
        .enq_en(chk_rd_qqq),
        .notFull(),
        .almostFull(chk_fifo_full),

        .first({chk_first, chk_first_addr}),
        .deq_en(fifo_deq),
        .notEmpty(chk_notEmpty)
        );


    t_mem_tag c0Rx_tag;
    t_cci_clData c0Rx_data;

    cci_mpf_prim_fifo_bram
      #(
        .N_DATA_BITS($bits(t_mem_tag) + $bits(t_cci_clData)),
        .N_ENTRIES(1024)
        )
      rsp_fifo
       (
        .clk,
        .reset,

        .enq_data({lineToTag(fiu.c0Rx.data), fiu.c0Rx.data}),
        // mdata[0] indicates whether the read is checked
        .enq_en(cci_c0Rx_isReadRsp(fiu.c0Rx) && fiu.c0Rx.hdr.mdata[0]),
        .notFull(),
        .almostFull(),

        .first({c0Rx_tag, c0Rx_data}),
        .deq_en(fifo_deq),
        .notEmpty(rsp_notEmpty)
        );

    //
    // Compare checker to CCI read responses.
    //
    always_ff @(posedge clk)
    begin
        if (state == STATE_RUN)
        begin
            if (fifo_deq)
            begin
                cnt_checked_rd <= cnt_checked_rd + t_counter'(1);

                if (c0Rx_tag != chk_first)
                begin
                    raise_error <= enable_checker;

                    if (! reset)
                    begin
                        $display("ERROR: Addr 0x%x, expected 0x%x, got 0x%x, line 0x%x",
                                 chk_first_addr,
                                 chk_first, c0Rx_tag,
                                 c0Rx_data);
                    end
                end
            end
        end

        if (reset || start_new_run)
        begin
            raise_error <= 1'b0;
            cnt_checked_rd <= t_counter'(0);
        end
    end


endmodule // test_afu
