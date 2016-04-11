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
`include "cci_mpf_csrs.vh"

//
// There is a single CSR (MMIO read/write) manager in MPF, shared by all
// shims.  We do this because the required buffering is large enough to be
// worth sharing across all shims.  When a shim is not present in a
// system the corresponding CSRs have no meaning.
//

// MMIO address range of MPF CSRs
parameter CCI_MPF_CSR_SIZE = CCI_MPF_VTP_CSR_SIZE + CCI_MPF_WRO_CSR_SIZE;

// Size in 64 bit words
parameter CCI_MPF_CSR_SIZE64 = (CCI_MPF_CSR_SIZE >> 3);

// Type for holding MPF CSR address as an offset from DFH_MMIO_BASE_ADDR
typedef logic [$clog2(CCI_MPF_CSR_SIZE64)-1:0] t_mpf_csr_offset;

// Offset of each shim's CSR range from feature list start.  This is
// similar to base addresses above, but the origin is the first feature
// managed by MPF.
parameter CCI_MPF_VTP_CSR_OFFSET = 0;
parameter CCI_MPF_WRO_CSR_OFFSET = CCI_MPF_VTP_CSR_OFFSET + CCI_MPF_VTP_CSR_SIZE;

// Size of the intermediate statistics counter bucket. These buckets
// are added periodically to the CSR memory by cci_mpf_shim_csr.
parameter CCI_MPF_STAT_CNT_WIDTH = 16;
typedef logic [CCI_MPF_STAT_CNT_WIDTH-1:0] t_cci_mpf_stat_cnt;

parameter CCI_MPF_CSR_NUM_STATS = 5;
typedef t_mpf_csr_offset [0:CCI_MPF_CSR_NUM_STATS-1] t_stat_csr_offset_vec;
typedef t_cci_mpf_stat_cnt [0:CCI_MPF_CSR_NUM_STATS-1] t_stat_upd_count_vec;


module cci_mpf_shim_csr
  #(
    // Instance ID reported in feature IDs of all device feature
    // headers instantiated under this instance of MPF.  If only a single
    // MPF instance is instantiated in the AFU then leaving the instance
    // ID at 1 is probably the right choice.
    parameter MPF_INSTANCE_ID = 1,

    // MMIO base address (byte level) allocated to MPF for feature lists
    // and CSRs.  The AFU allocating this module must build at least
    // a device feature header (DFH) for the AFU.  The chain of device
    // features in the AFU must then point to the base address here
    // as another feature in the chain.  MPF will continue the list.
    // The base address here must point to a region that is at least
    // CCI_MPF_MMIO_SIZE bytes.
    parameter DFH_MMIO_BASE_ADDR = 0,

    // Address of the next device feature header outside MPF.  MPF will
    // terminate the feature list if the next address is 0.
    parameter DFH_MMIO_NEXT_ADDR = 0,

    // Is shims enabled?
    parameter MPF_ENABLE_VTP = 0,
    parameter MPF_ENABLE_WRO = 0
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    // CSR connections to other shims
    cci_mpf_csrs.csr csrs,
    cci_mpf_csrs.csr_events events
    );

    logic reset;
    assign reset = fiu.reset;
    assign afu.reset = fiu.reset;

    // Most connections flow straight through and are, at most, read in this shim.
    assign fiu.c0Tx = afu.c0Tx;
    assign afu.c0TxAlmFull = fiu.c0TxAlmFull;
    assign fiu.c1Tx = afu.c1Tx;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull;

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;

    localparam CCI_MPF_CSR_LAST = DFH_MMIO_BASE_ADDR + CCI_MPF_CSR_SIZE;

    // Base address of each shim's CSR range
    localparam CCI_MPF_VTP_CSR_BASE = DFH_MMIO_BASE_ADDR;
    localparam CCI_MPF_WRO_CSR_BASE = CCI_MPF_VTP_CSR_BASE + CCI_MPF_VTP_CSR_SIZE;


    // Register incoming requests
    t_if_cci_c0_Rx c0_rx;
    always_ff @(posedge clk)
    begin
        c0_rx <= fiu.c0Rx;
    end


    // ====================================================================
    //
    //  CSR writes from host to FPGA
    //
    // ====================================================================

    // Check for a CSR address match
    function automatic logic csrAddrMatches(
        input t_if_cci_c0_Rx c0Rx,
        input int c);

        // Target address.  The CSR space is 4-byte addressable.  The
        // low 2 address bits must be 0 and aren't transmitted.
        t_cci_mmioAddr tgt = t_cci_mmioAddr'(c >> 2);

        // Actual address sent in CSR write.
        t_cci_mmioAddr addr = cci_csr_getAddress(c0Rx);

        return cci_csr_isWrite(c0Rx) && (addr == tgt);
    endfunction

    //
    // VTP CSR writes (host to FPGA)
    //
    t_cci_clAddr page_table_base;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            csrs.vtp_in_mode <= t_cci_mpf_vtp_csr_mode'(0);
            csrs.vtp_in_page_table_base_valid <= 1'b0;
        end
        else if (cci_csr_isWrite(c0_rx))
        begin
            if (csrAddrMatches(c0_rx, CCI_MPF_VTP_CSR_BASE +
                                      CCI_MPF_VTP_CSR_MODE))
            begin
                csrs.vtp_in_mode <= t_cci_mpf_vtp_csr_mode'(c0_rx.data);
            end
            else
            begin
                // Invalidate page table held only one cycle
                csrs.vtp_in_mode.inval_translation_cache <= 1'b0;
            end

            if (csrAddrMatches(c0_rx, CCI_MPF_VTP_CSR_BASE +
                                      CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR))
            begin
                csrs.vtp_in_page_table_base <= t_cci_clAddr'(c0_rx.data);
                csrs.vtp_in_page_table_base_valid <= 1'b1;
            end
        end
    end


    // ====================================================================
    //
    //  CSR reads from host
    //
    // ====================================================================

    //
    // Hold response state in LUTRAM
    //
    logic csr_mem_rd_en;
    t_mpf_csr_offset csr_mem_rd_idx;
    logic csr_mem_rd_rdy;

    logic [63:0] csr_mem_rd_val;
    logic csr_mem_rd_val_valid;

    logic csr_mem_wr_en;
    logic [63:0] csr_mem_wr_val;
    t_mpf_csr_offset csr_mem_wr_idx;

    cci_mpf_shim_csr_rd_memory
      #(
        .MPF_INSTANCE_ID(MPF_INSTANCE_ID),
        .DFH_MMIO_NEXT_ADDR(DFH_MMIO_NEXT_ADDR),

        .CCI_MPF_VTP_CSR_BASE(CCI_MPF_VTP_CSR_BASE),
        .CCI_MPF_WRO_CSR_BASE(CCI_MPF_WRO_CSR_BASE),
        .MPF_ENABLE_VTP(MPF_ENABLE_VTP),
        .MPF_ENABLE_WRO(MPF_ENABLE_WRO)
        )
      rd_mem
       (
        .clk,
        .reset,

        .csr_mem_rd_en,
        .csr_mem_rd_idx,
        .csr_mem_rd_rdy,

        .csr_mem_rd_val,
        .csr_mem_rd_val_valid,

        .csr_mem_wr_en,
        .csr_mem_wr_idx,
        .csr_mem_wr_val
        );


    //
    // Statistics counters
    //
    logic stat_upd_rdy;
    logic stat_upd_en;
    t_stat_csr_offset_vec stat_upd_offset_vec;
    t_stat_upd_count_vec stat_upd_count_vec;

    cci_mpf_shim_csr_events
      stats
       (
        .clk,
        .reset,

        .stat_upd_rdy,
        .stat_upd_en,
        .stat_upd_offset_vec,
        .stat_upd_count_vec,

        .events
        );


    t_if_ccip_c2_Tx c2_rsp;
    logic c2_rsp_en;

    // Forward responses to host, either generated locally (c2_rsp) or from
    // the AFU.
    always_ff @(posedge clk)
    begin
        fiu.c2Tx <= (c2_rsp_en ? c2_rsp : afu.c2Tx);
    end

    logic mmio_req_valid;
    t_mpf_csr_offset mmio_req_addr;
    t_ccip_tid mmio_req_tid;

    // New MMIO read request?
    logic mmio_read_start;
    logic mmio_read_active;
    assign mmio_read_start = mmio_req_valid && ! mmio_read_active &&
                             csr_mem_rd_rdy;

    // Give priority to existing MMIO responses from the AFU
    assign c2_rsp_en = ! afu.c2Tx.mmioRdValid && c2_rsp.mmioRdValid;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            c2_rsp.mmioRdValid <= 1'b0;
            mmio_read_active <= 1'b0;
        end
        else if (c2_rsp_en)
        begin
            // Read response forwarded to host
            c2_rsp.mmioRdValid <= 1'b0;
            mmio_read_active <= 1'b0;
        end
        else
        begin
            if (mmio_read_start)
            begin
                // New MMIO read request.  Request the value of the register.
                mmio_read_active <= 1'b1;
                c2_rsp.hdr.tid <= mmio_req_tid;
            end

            if (mmio_read_active && ! c2_rsp.mmioRdValid && csr_mem_rd_val_valid)
            begin
                // Got the CSR value.  Store it in the output buffer.
                c2_rsp.mmioRdValid <= 1'b1;
                c2_rsp.data <= csr_mem_rd_val;
            end
        end
    end


    //
    // This platform has MMIO.  Up to 64 MMIO reads may be in flight.
    // Buffer incoming read requests since the read response port
    // contends with other responders.
    //

    logic mmio_req_enq_en;

    // Address of incoming request
    t_cci_mmioAddr mmio_req_addr_in;
    assign mmio_req_addr_in = cci_csr_getAddress(c0_rx);

    t_cci_mmioAddr mmio_req_addr_in_offset;
    assign mmio_req_addr_in_offset = mmio_req_addr_in -
                                     t_cci_mmioAddr'(DFH_MMIO_BASE_ADDR >> 2);

    // Store incoming requests only if the address is possibly in range
    assign mmio_req_enq_en = cci_csr_isRead(c0_rx) &&
                             mmio_req_addr_in >= (DFH_MMIO_BASE_ADDR >> 2) &&
                             mmio_req_addr_in < (CCI_MPF_CSR_LAST >> 2);

    // Register FIFO input for timing
    logic [$bits(t_mpf_csr_offset) + CCIP_TID_WIDTH - 1 : 0] req_fifo_in;
    logic req_fifo_in_en;

    always_ff @(posedge clk)
    begin
        // Offset comes in as an index to 32 bit words.  Convert it to a 64
        // bit word index, which is all VTP uses for CSR addresses.
        req_fifo_in <= { mmio_req_addr_in_offset[1 +: $bits(t_mpf_csr_offset)],
                         cci_csr_getTid(c0_rx) };
        req_fifo_in_en <= mmio_req_enq_en;
    end

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_mpf_csr_offset) + CCIP_TID_WIDTH),
        .N_ENTRIES(64)
        )
      req_fifo
        (
         .clk,
         .reset,
         // Store only the MMIO address bits needed for decode
         .enq_data(req_fifo_in),
         .enq_en(req_fifo_in_en),
         .notFull(),
         .almostFull(),
         .first({mmio_req_addr, mmio_req_tid}),
         .deq_en(mmio_read_start),
         .notEmpty(mmio_req_valid)
         );


    enum logic [1:0] {
        STAT_IDLE,
        STAT_PROCESS_VEC,
        STAT_UPDATE,
        STAT_WRITEBACK
    }
    stat_upd_state;

    assign stat_upd_rdy = (stat_upd_state == STAT_IDLE);

    t_stat_csr_offset_vec stat_upd_offsets;
    t_stat_upd_count_vec stat_upd_counts;

    logic stat_bucket_upd;
    logic stat_bucket_reset;
    logic [63:0] stat_bucket_wr_val;

    //
    // State machine for processing statistics updates.
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            stat_upd_state <= STAT_IDLE;

            // First update pass will reset all stored counters
            stat_bucket_reset <= 1'b1;
        end
        else
        begin
            case (stat_upd_state)
              STAT_IDLE:
                begin
                    if (stat_upd_en)
                    begin
                        // Update statistics counters from vector of
                        // small intermediate counters requested by stats
                        // module.
                        stat_upd_state <= STAT_PROCESS_VEC;
                    end

                    stat_upd_offsets <= stat_upd_offset_vec;
                    stat_upd_counts <= stat_upd_count_vec;
                end

              STAT_PROCESS_VEC:
                begin
                    // Is the CSR memory available for reading?
                    if (stat_bucket_upd)
                    begin
                        // Started the read for one entry
                        stat_upd_state <= STAT_UPDATE;
                    end
                end

              STAT_UPDATE:
                begin
                    // Wait for CSR memory read response
                    if (csr_mem_rd_val_valid)
                    begin
                        stat_upd_state <= STAT_WRITEBACK;
                    end

                    // First pass after reset treats the buckets as having
                    // zero and overwrites the old value.  Subsequent passes
                    // add to the existing value.
                    if (! stat_bucket_reset)
                    begin
                        stat_bucket_wr_val <= csr_mem_rd_val +
                                              64'(stat_upd_counts[0]);
                    end
                    else
                    begin
                        stat_bucket_wr_val <= 64'(stat_upd_counts[0]);
                    end
                end

              STAT_WRITEBACK:
                begin
                    if (csr_mem_wr_en)
                    begin
                        // Writeback complete.  Either process the next
                        // bucket or done with current update list.
                        if (stat_upd_offsets[1] != t_mpf_csr_offset'(0))
                        begin
                            stat_upd_state <= STAT_PROCESS_VEC;
                        end
                        else
                        begin
                            stat_upd_state <= STAT_IDLE;
                            stat_bucket_reset <= 1'b0;
                        end

                        // Shift the incremental counter update vector
                        for (int s = 0; s < CCI_MPF_CSR_NUM_STATS - 1; s = s + 1)
                        begin
                            stat_upd_offsets[s] <= stat_upd_offsets[s + 1];
                            stat_upd_counts[s] <= stat_upd_counts[s + 1];
                        end

                        stat_upd_offsets[CCI_MPF_CSR_NUM_STATS-1] <=
                            t_mpf_csr_offset'(0);
                    end
                end
            endcase
        end
    end

    assign stat_bucket_upd = csr_mem_rd_rdy && ! mmio_req_valid && 
                             (stat_upd_state == STAT_PROCESS_VEC);

    assign csr_mem_rd_en = mmio_read_start || stat_bucket_upd;
    assign csr_mem_rd_idx = mmio_read_start ? mmio_req_addr : stat_upd_offsets[0];

    // Don't write while reads are in flight
    assign csr_mem_wr_en = (stat_upd_state == STAT_WRITEBACK) && csr_mem_rd_rdy;
    assign csr_mem_wr_idx = stat_upd_offsets[0];
    assign csr_mem_wr_val = stat_bucket_wr_val;

endmodule // cci_mpf_shim_csr


module cci_mpf_shim_csr_events
   (
    input  logic clk,
    input  logic reset,

    // cci_mpf_shim_csr ready to accept updated counts?
    input  logic stat_upd_rdy,
    // Update counts
    output logic stat_upd_en,
    // Indices of CSR read register being updated
    output t_stat_csr_offset_vec stat_upd_offset_vec,
    // Counts to add to corresponding CSR read register
    output t_stat_upd_count_vec stat_upd_count_vec,

    cci_mpf_csrs.csr_events events
    );

    logic consume_counters;

    t_cci_mpf_stat_cnt vtp_4kb_hits;
    t_cci_mpf_stat_cnt vtp_4kb_misses;
    t_cci_mpf_stat_cnt vtp_2mb_hits;
    t_cci_mpf_stat_cnt vtp_2mb_misses;
    t_cci_mpf_stat_cnt vtp_pt_walk_busy_cycles;


    // ====================================================================
    //
    //  Write local counter updates to CSR read memory periodically
    //
    // ====================================================================

    logic [10:0] upd_counts;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            upd_counts <= 10'b0;
        end
        else if (consume_counters)
        begin
            upd_counts <= 10'b0;
        end
        else
        begin
            upd_counts <= upd_counts + 10'b1;
        end
    end

    assign stat_upd_en = consume_counters;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            consume_counters = 1'b0;
        end
        else
        begin
            consume_counters <= (upd_counts[10] == 1'b1) && stat_upd_rdy;
        end
    end

    always_comb
    begin
        stat_upd_offset_vec[0] =
            t_mpf_csr_offset'((CCI_MPF_VTP_CSR_OFFSET +
                               CCI_MPF_VTP_CSR_STAT_4KB_TLB_NUM_HITS) >> 3);
        stat_upd_count_vec[0] = vtp_4kb_hits;

        stat_upd_offset_vec[1] =
            t_mpf_csr_offset'((CCI_MPF_VTP_CSR_OFFSET +
                               CCI_MPF_VTP_CSR_STAT_4KB_TLB_NUM_MISSES) >> 3);
        stat_upd_count_vec[1] = vtp_4kb_misses;

        stat_upd_offset_vec[2] =
            t_mpf_csr_offset'((CCI_MPF_VTP_CSR_OFFSET +
                               CCI_MPF_VTP_CSR_STAT_2MB_TLB_NUM_HITS) >> 3);
        stat_upd_count_vec[2] = vtp_2mb_hits;

        stat_upd_offset_vec[3] =
            t_mpf_csr_offset'((CCI_MPF_VTP_CSR_OFFSET +
                               CCI_MPF_VTP_CSR_STAT_2MB_TLB_NUM_MISSES) >> 3);
        stat_upd_count_vec[3] = vtp_2mb_misses;

        stat_upd_offset_vec[4] =
            t_mpf_csr_offset'((CCI_MPF_VTP_CSR_OFFSET +
                               CCI_MPF_VTP_CSR_STAT_PT_WALK_BUSY_CYCLES) >> 3);
        stat_upd_count_vec[4] = vtp_pt_walk_busy_cycles;
    end


    // ====================================================================
    //
    //  Update counters from event triggers.
    //
    // ====================================================================

    // Same as counters above, but 0 if counters are consumed this cycle
    t_cci_mpf_stat_cnt vtp_4kb_hits_cur;
    t_cci_mpf_stat_cnt vtp_4kb_misses_cur;
    t_cci_mpf_stat_cnt vtp_2mb_hits_cur;
    t_cci_mpf_stat_cnt vtp_2mb_misses_cur;
    t_cci_mpf_stat_cnt vtp_pt_walk_busy_cycles_cur;
    assign vtp_4kb_hits_cur = (consume_counters ? t_cci_mpf_stat_cnt'(0) : vtp_4kb_hits);
    assign vtp_4kb_misses_cur = (consume_counters ? t_cci_mpf_stat_cnt'(0) : vtp_4kb_misses);
    assign vtp_2mb_hits_cur = (consume_counters ? t_cci_mpf_stat_cnt'(0) : vtp_2mb_hits);
    assign vtp_2mb_misses_cur = (consume_counters ? t_cci_mpf_stat_cnt'(0) : vtp_2mb_misses);
    assign vtp_pt_walk_busy_cycles_cur = (consume_counters ? t_cci_mpf_stat_cnt'(0) : vtp_pt_walk_busy_cycles);


    logic [1:0] vtp_4kb_hits_incr;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            vtp_4kb_hits <= t_cci_mpf_stat_cnt'(0);
            vtp_4kb_hits_incr <= 2'd0;
        end
        else
        begin
            vtp_4kb_hits_incr <= 2'(events.vtp_out_event_4kb_hit_c0) +
                                 2'(events.vtp_out_event_4kb_hit_c1);
            vtp_4kb_hits <= vtp_4kb_hits_cur + t_cci_mpf_stat_cnt'(vtp_4kb_hits_incr);
        end
    end

    logic vtp_4kb_misses_incr;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            vtp_4kb_misses <= t_cci_mpf_stat_cnt'(0);
            vtp_4kb_misses_incr <= 1'b0;
        end
        else
        begin
            vtp_4kb_misses_incr <= events.vtp_out_event_4kb_miss;
            vtp_4kb_misses <= vtp_4kb_misses_cur + t_cci_mpf_stat_cnt'(vtp_4kb_misses_incr);
        end
    end


    logic [1:0] vtp_2mb_hits_incr;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            vtp_2mb_hits <= t_cci_mpf_stat_cnt'(0);
            vtp_2mb_hits_incr <= 2'd0;
        end
        else
        begin
            vtp_2mb_hits_incr <= 2'(events.vtp_out_event_2mb_hit_c0) +
                                 2'(events.vtp_out_event_2mb_hit_c1);
            vtp_2mb_hits <= vtp_2mb_hits_cur + t_cci_mpf_stat_cnt'(vtp_2mb_hits_incr);
        end
    end

    logic vtp_2mb_misses_incr;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            vtp_2mb_misses <= t_cci_mpf_stat_cnt'(0);
            vtp_2mb_misses_incr <= 1'b0;
        end
        else
        begin
            vtp_2mb_misses_incr <= events.vtp_out_event_2mb_miss;
            vtp_2mb_misses <= vtp_2mb_misses_cur + t_cci_mpf_stat_cnt'(vtp_2mb_misses_incr);
        end
    end

    logic vtp_pt_walk_busy_cycles_incr;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            vtp_pt_walk_busy_cycles <= t_cci_mpf_stat_cnt'(0);
            vtp_pt_walk_busy_cycles_incr <= 1'b0;
        end
        else
        begin
            vtp_pt_walk_busy_cycles_incr <= events.vtp_out_event_pt_walk_busy;
            vtp_pt_walk_busy_cycles <= vtp_pt_walk_busy_cycles_cur + t_cci_mpf_stat_cnt'(vtp_pt_walk_busy_cycles_incr);
        end
    end

endmodule // cci_mpf_shim_csr_events


//
// Manage the backing storage for CSR reads.
//
// The memory is simple LUTRAM, but read access is managed with a complex
// protocol in order treat reads as multi-cycle operations.  The read address
// is registered and held constant and the synthesis tool is given a timing
// contraint that allows read values to settle over multiple cycles.
//
module cci_mpf_shim_csr_rd_memory
  #(
    parameter MPF_INSTANCE_ID = 1,
    parameter DFH_MMIO_NEXT_ADDR = 0,

    parameter CCI_MPF_VTP_CSR_BASE = 0,
    parameter CCI_MPF_WRO_CSR_BASE = 0,
    parameter MPF_ENABLE_VTP = 0,
    parameter MPF_ENABLE_WRO = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic csr_mem_rd_en,
    input  t_mpf_csr_offset csr_mem_rd_idx,
    output logic csr_mem_rd_rdy,

    output logic [63:0] csr_mem_rd_val,
    output logic csr_mem_rd_val_valid,

    input  logic csr_mem_wr_en,
    input  t_mpf_csr_offset csr_mem_wr_idx,
    input  logic [63:0] csr_mem_wr_val
    );

    reg [63:0] csr_mem[0:CCI_MPF_CSR_SIZE64 - 1] /* synthesis ramstyle = "MLAB, no_rw_check" */;

    logic [63:0] cciMpfCSRMemRdVal /* synthesis keep */;
    assign csr_mem_rd_val = cciMpfCSRMemRdVal;

    //
    // Register csr_mem_rd_idx and hold it for 2 cycles to complete a read.
    // Reads are not pipelined.  New reads aren't allowed to start until the
    // current one completes.  Upon completion, csr_mem_rd_val_valid is
    // asserted for one cycle.
    //
    logic [1:0] rd_active;
    assign csr_mem_rd_rdy = ~(|(rd_active));
    assign csr_mem_rd_val_valid = rd_active[1];

    t_mpf_csr_offset rd_addr;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_active <= 2'b0;
        end
        else
        begin
            rd_active[0] <= csr_mem_rd_en;
            rd_active[1] <= rd_active[0];

            if (csr_mem_rd_en)
            begin
                rd_addr <= csr_mem_rd_idx;

                assert (csr_mem_rd_rdy) else
                    $fatal("cci_mpf_shim_csr.sv: Read request when not ready!");
            end
        end
    end


    assign cciMpfCSRMemRdVal = csr_mem[rd_addr];
    always @(posedge clk)
    begin
        if (csr_mem_wr_en)
        begin
            csr_mem[csr_mem_wr_idx] <= csr_mem_wr_val;

            assert (csr_mem_rd_rdy) else
                $fatal("cci_mpf_shim_csr.sv: Write request not permitted during read!");
        end
    end


    //
    // Initial state of readable CSR memory holds device feature headers
    // and other constant state.  Statistics will be incorporated at run
    // time.
    //
    initial
    begin
        t_ccip_dfh vtp_dfh;
        logic [127:0] vtp_uid;
        t_ccip_dfh wro_dfh;
        logic [127:0] wro_uid;

        // Construct the feature headers for each feature
        vtp_dfh = ccip_dfh_defaultDFH();
        vtp_dfh.f_type = eFTYP_BBB;
        vtp_dfh.id = t_ccip_feature_id'(MPF_INSTANCE_ID);
        vtp_dfh.next = CCI_MPF_VTP_CSR_SIZE;
        if (MPF_ENABLE_VTP != 0)
        begin
            // UID of VTP feature (from cci_mpf_csrs.h)
            vtp_uid = 128'hc8a2982f_ff96_42bf_a705_45727f501901;
        end
        else
        begin
            vtp_uid = 128'h0;
        end

        wro_dfh = ccip_dfh_defaultDFH();
        wro_dfh.f_type = eFTYP_BBB;
        wro_dfh.id = t_ccip_feature_id'(MPF_INSTANCE_ID);
        if (MPF_ENABLE_WRO != 0)
        begin
            // UID of WRO feature (from cci_mpf_csrs.h)
            wro_uid = 128'h56b06b48_9dd7_4004_a47e_0681b4207a6d;
        end
        else
        begin
            wro_uid = 128'h0;
        end

        if (DFH_MMIO_NEXT_ADDR == 0)
        begin
            // WRO is the last feature in the AFU's list
            wro_dfh.next = CCI_MPF_WRO_CSR_SIZE;
            wro_dfh.eol = 1'b1;
        end
        else
        begin
            // Point to the next feature (outside of MPF)
            wro_dfh.next = DFH_MMIO_NEXT_ADDR - CCI_MPF_WRO_CSR_BASE;
        end

        // VTP DFH (device feature header)
        csr_mem[(CCI_MPF_VTP_CSR_OFFSET + CCI_MPF_VTP_CSR_DFH) >> 3] = vtp_dfh;

        // VTP UID low
        csr_mem[(CCI_MPF_VTP_CSR_OFFSET + CCI_MPF_VTP_CSR_ID_L) >> 3] = vtp_uid[63:0];

        // VTP UID high
        csr_mem[(CCI_MPF_VTP_CSR_OFFSET + CCI_MPF_VTP_CSR_ID_H) >> 3] = vtp_uid[127:64];

        // WRO DFH (device feature header)
        csr_mem[(CCI_MPF_WRO_CSR_OFFSET + CCI_MPF_WRO_CSR_DFH) >> 3] = wro_dfh;

        // WRO UID low
        csr_mem[(CCI_MPF_WRO_CSR_OFFSET + CCI_MPF_WRO_CSR_ID_L) >> 3] = wro_uid[63:0];

        // WRO UID high
        csr_mem[(CCI_MPF_WRO_CSR_OFFSET + CCI_MPF_WRO_CSR_ID_H) >> 3] = wro_uid[127:64];
    end

endmodule // cci_mpf_shim_csr_rd_memory
