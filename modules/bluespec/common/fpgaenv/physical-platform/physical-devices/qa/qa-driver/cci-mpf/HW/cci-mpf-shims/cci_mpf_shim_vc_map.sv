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

`include "cci_mpf_prim_hash.vh"


//
// Map read/write requests to eVC_VA to specific physical channels.  Mapping
// is a function of addresses such that a read or write to a given location
// is always mapped to the same channel.  This makes it possible to be sure
// that a value written is committed to memory before a later read or write.
// This method of tracking write responses works only within a single channel.
// Cross-channel commits require WrFence to eVC_VA, which is expensive.
//
// Throughput using eVC_VA is typically higher than throughput using explicit
// channel mapping.  This module seeks to optimize the ratio of requests
// for maximum throughput on a given hardware platform.
//


module cci_mpf_shim_vc_map
  #(
    // Allow dynamic mapping in response to traffic patterns?
    parameter ENABLE_DYNAMIC_VC_MAPPING = 1,

    // Maximum number in-flight requests per channel.
    parameter MAX_ACTIVE_REQS = 128,

    // Mdata index that can be used to tag a private WrFence.
    parameter RESERVED_MDATA_IDX = -1
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    cci_mpf_csrs.vc_map csrs,
    cci_mpf_csrs.vc_map_events events
    );

    // How often to sample for a new ratio (cycles)
    localparam MAX_SAMPLE_CYCLES_RADIX = 16;

    // Sample in groups of N_SAMPLE_REGIONS.  When N_SAMPLE_REGIONS successive
    // regions all have the same recommended configuration then update the
    // channel mapping ratio.
    localparam N_SAMPLE_REGIONS = 16;


    assign afu.reset = fiu.reset;

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end


    assign fiu.c2Tx = afu.c2Tx;

    //
    // Response channels
    //
    logic is_vc_map_wrfence_rsp;

    always_comb
    begin
        afu.c0Rx = fiu.c0Rx;

        // Drop locally generated WrFence
        afu.c1Rx = cci_mpf_c1TxMaskValids(fiu.c1Rx, ! is_vc_map_wrfence_rsp);
    end


    //
    // Request flow control
    //
    logic block_tx_traffic;
    always_comb
    begin
        afu.c0TxAlmFull = fiu.c0TxAlmFull || block_tx_traffic;
        afu.c1TxAlmFull = fiu.c1TxAlmFull || block_tx_traffic;
    end


    // ====================================================================
    //
    //   Mapping control
    //
    // ====================================================================

    logic mapping_disabled;
    logic dynamic_mapping_disabled;
    logic map_all;

    // Fraction of requests to map to VL0 (of 64)
    typedef logic [5:0] t_map_ratio;
    t_map_ratio ratio_vl0;
    logic always_use_vl0;

`ifdef MPF_PLATFORM_OME
    // Don't care (only one physical channel)
    localparam RATIO_VL0_DEFAULT = t_map_ratio'(16);
`elsif MPF_PLATFORM_BDX
    // Default ratio is 2 VL0 : 3 VH0 : 3 VH1 which is a reasonable compromise
    // for CCI-P on BDX.
    localparam RATIO_VL0_DEFAULT = t_map_ratio'(16);
`else
    ** ERROR: Unknown platform
`endif

    // Should request be mapped?
    function automatic logic req_needs_mapping(t_cci_vc vc_sel);
        return ((vc_sel == eVC_VA) || map_all);
    endfunction

    // Set when dynamic logic below suggests a better ratio.
    logic new_ratio_vl0_en;
    t_map_ratio new_ratio_vl0;

    logic [$clog2(MAX_SAMPLE_CYCLES_RADIX)-1 : 0] sample_interval_idx;
    // Default to sampling every 1K cycles
    localparam DEFAULT_SAMPLE_INTERVAL_IDX = 10;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            mapping_disabled <= 1'b0;
            dynamic_mapping_disabled <= (ENABLE_DYNAMIC_VC_MAPPING == 0);
            sample_interval_idx <= DEFAULT_SAMPLE_INTERVAL_IDX;

            map_all <= 1'b0;
            ratio_vl0 <= RATIO_VL0_DEFAULT;
            always_use_vl0 <= 1'b0;
        end
        else if (csrs.vc_map_ctrl_valid)
        begin
            // See cci_mpf_csrs.h for bit assignments in the control word.
            mapping_disabled <= ~ csrs.vc_map_ctrl[0];
            dynamic_mapping_disabled <= ~ csrs.vc_map_ctrl[1];
            sample_interval_idx <=
                (csrs.vc_map_ctrl[5:2] != 4'b0) ? csrs.vc_map_ctrl[5:2] :
                                                  DEFAULT_SAMPLE_INTERVAL_IDX;

            map_all <= csrs.vc_map_ctrl[6];
            ratio_vl0 <= csrs.vc_map_ctrl[7] ? csrs.vc_map_ctrl[13:8] :
                                               RATIO_VL0_DEFAULT;
            always_use_vl0 <= csrs.vc_map_ctrl[14];
        end
        else if (new_ratio_vl0_en)
        begin
            // Dynamic logic has suggested a better ratio
            ratio_vl0 <= new_ratio_vl0;
            always_use_vl0 <= 1'b0;
        end
    end


    //
    // Request mapping function.  The mapping is consistent for a given address.
    //
    function automatic t_ccip_vc mapVA(t_ccip_clAddr addr);
        t_ccip_vc vc;

        // The hash function operates on 32 bits of the address.  Drop the
        // low address bits that are covered by multi-line requests so that
        // a given address always winds up hashed to the same channel,
        // independent of the access size.
        logic [31:0] a = addr[$bits(t_ccip_clNum) +: 32];

        // Input bits 4 and 5 are underrepresented in the low 6 bits of
        // the CRC-32 hash.  Swap them with less important higher bits
        // of the address.
        logic [31:0] addr_swizzle = { a[29:4], a[31:30], a[3:0] };

        // Hash addresses for even distribution within the mapping table,
        // attempting to have the mapping be independent of the memory
        // access pattern.
        t_map_ratio hashed_idx = t_map_ratio'(hash32(addr_swizzle));

        // Now that entries are hashed we can just use ranges in the mapping.
        if ((hashed_idx < ratio_vl0) || always_use_vl0)
        begin
            vc = eVC_VL0;
        end
        else
        begin
            // Choose randomly with equal weight between PCIe channels
            vc = (hashed_idx[0] ? eVC_VH0 : eVC_VH1);
        end

        return vc;
    endfunction


    //
    // Compute the possible VA to physical mapping for both the read and
    // write request channels and register the incoming requests.  The
    // mapped channel may be used in the subsequent cycle.
    //
    t_if_cci_mpf_c0_Tx c0_tx;
    t_ccip_vc c0_vc_map;
    t_if_cci_mpf_c1_Tx c1_tx;
    t_ccip_vc c1_vc_map;

    always_ff @(posedge clk)
    begin
        c0_tx <= afu.c0Tx;
        c0_vc_map <= mapVA(cci_mpf_c0_getReqAddr(afu.c0Tx.hdr));

        c1_tx <= afu.c1Tx;
        c1_vc_map <= mapVA(cci_mpf_c1_getReqAddr(afu.c1Tx.hdr));
    end

    always_comb
    begin
        fiu.c0Tx = c0_tx;

        if (! mapping_disabled &&
            cci_mpf_c0_getReqMapVA(c0_tx.hdr) &&
            req_needs_mapping(c0_tx.hdr.base.vc_sel))
        begin
            fiu.c0Tx.hdr.base.vc_sel = c0_vc_map;
        end
    end

    logic emit_wrfence_en;

    always_comb
    begin
        fiu.c1Tx = c1_tx;

        if (! mapping_disabled &&
            cci_mpf_c1_getReqMapVA(c1_tx.hdr) &&
            req_needs_mapping(c1_tx.hdr.base.vc_sel))
        begin
            fiu.c1Tx.hdr.base.vc_sel = c1_vc_map;
        end

        //
        // Changing to a new ratio?  This will only be set when there is
        // no incoming request from the AFU.  Emit a WrFence on eVA_VC to
        // force full synchronization before changing the address mapping.
        //
        if (emit_wrfence_en)
        begin
            t_cci_mpf_ReqMemHdrParams wrfence_params;
            wrfence_params = cci_mpf_defaultReqHdrParams(0);
            wrfence_params.vc_sel = eVC_VA;

            fiu.c1Tx.hdr = cci_mpf_c1_genReqHdr(eREQ_WRFENCE,
                                                t_cci_clAddr'(0),
                                                t_cci_mdata'(1 << RESERVED_MDATA_IDX),
                                                wrfence_params);
            fiu.c1Tx.valid = 1'b1;
        end
    end


    // ====================================================================
    // 
    //   Pick the right ratio for the current traffic and hardware.
    //
    // ====================================================================

    function automatic t_map_ratio pickRatioVL0(logic mostlyRead,
                                                logic mostlyWrite,
                                                t_ccip_clLen reqLen);
        int r;

`ifdef MPF_PLATFORM_OME

        // Mapping is irrelevant.  The HW has only one channel.
        r = 16;

`elsif MPF_PLATFORM_BDX

        //
        // The following memory throughput was determined experimentally
        // for the Arria 10 on BDX.  The chart shows full performance in
        // NLB mode 3 for read, write and trput in GB/s.  The first group
        // is single line accesses, followed by 2 and then 4 line requests.
        // Ratios are indicated in 64ths -- the same as the mapping above.
        // Peak performance is marked with an X.
        //
        //
        //                     BDX Arria 10 Xeon+FPGA
        // Ratio
        // (VL0:VH0:VH1) Read 1 CL     Write 1 CL    Trput R 1 CL  Trput W 1 CL
        // VA (no map)   16.7          15.4          11.1          10.9
        // 28:18:18      16.9 X        11.0          7.5           7.5
        // 24:20:20      16.1          13.3          8.7           8.9
        // 20:22:22      14.5          15.2 X        10.7 X        10.8 X
        // 16:24:24      13.3          14.0          9.9           10.0
        // 12:26:26      12.3          12.9          9.1           9.3
        //
        // Ratio
        // (VL0:VH0:VH1) Read 2 CL     Write 2 CL    Trput R 2 CL  Trput W 2 CL
        // VA (no map)   19.2          17.6          14.5          13.8
        // 28:18:18      17.0          11.0          7.6           7.8
        // 24:20:20      18.9 X        13.3          8.8           9.0
        // 20:22:22      16.9          16.0          10.8          11.0
        // 16:24:24      16.0          16.7 X        13.8 X        13.9 X
        // 12:26:26      14.8          15.4          12.9          12.9
        //
        // Ratio
        // (VL0:VH0:VH1) Read 4 CL     Write 4 CL    Trput R 4 CL  Trput W 4 CL
        // VA (no map)   18.9          19.0          15.8          15.6
        // 28:18:18      16.7          10.9          7.5           7.6
        // 24:20:20      19.4 X        13.3          8.6           8.8
        // 20:22:22      18.4          16.0          10.6          10.8
        // 16:24:24      16.8          18.4 X        13.4          13.5
        // 12:26:26      15.6          17.0          15.3 X        15.4 X
        //

        if (mostlyRead)
        begin
            case (reqLen)
              eCL_LEN_1: r = 28;
                default: r = 24;
            endcase
        end
        else if (mostlyWrite)
        begin
            case (reqLen)
              eCL_LEN_1: r = 20;
                default: r = 16;
            endcase
        end
        else
        begin
            case (reqLen)
              eCL_LEN_1: r = 20;
              eCL_LEN_2: r = 16;
                default: r = 12;
            endcase
        end

`else

    ** ERROR: Unknown platform

`endif

        return t_map_ratio'(r);
    endfunction


    // ====================================================================
    //
    //   Act on sampled data.
    //
    // ====================================================================

    typedef enum logic [1:0] {
        CCI_MPF_VC_MAP_SAMPLING,
        CCI_MPF_VC_MAP_EMIT_WRFENCE,
        CCI_MPF_VC_MAP_WAIT_WRFENCE_RSP,
        CCI_MPF_VC_MAP_WAIT_READS
    }
    t_cci_mpf_vc_map_state;
    t_cci_mpf_vc_map_state state;

    logic req_ratio_vl0_en;
    t_map_ratio req_ratio_vl0;

    logic [$clog2(MAX_ACTIVE_REQS)-1 : 0] num_outstanding_reads;

    //
    // Primary state machine.  When a new ratio is requested a WrFence must
    // be emitted and traffic stopped until all channels are synchronized.
    //
    always_ff @(posedge clk)
    begin
        case (state)
          CCI_MPF_VC_MAP_SAMPLING:
            begin
                // New request to change the ratio?
                if (req_ratio_vl0_en &&
                    ! mapping_disabled &&
                    ! dynamic_mapping_disabled &&
                    (req_ratio_vl0 != ratio_vl0))
                begin
                    new_ratio_vl0 <= req_ratio_vl0;

                    block_tx_traffic <= 1'b1;
                    state <= CCI_MPF_VC_MAP_EMIT_WRFENCE;
                end
            end

          CCI_MPF_VC_MAP_EMIT_WRFENCE:
            begin
                if (emit_wrfence_en)
                begin
                    state <= CCI_MPF_VC_MAP_WAIT_WRFENCE_RSP;
                end
            end

          CCI_MPF_VC_MAP_WAIT_WRFENCE_RSP:
            begin
                if (is_vc_map_wrfence_rsp)
                begin
                    new_ratio_vl0_en <= 1'b1;
                    events.vc_map_out_event_mapping_changed <= 1'b1;
                    state <= CCI_MPF_VC_MAP_WAIT_READS;
                end
            end

          CCI_MPF_VC_MAP_WAIT_READS:
            begin
                new_ratio_vl0_en <= 1'b0;
                events.vc_map_out_event_mapping_changed <= 1'b0;

                // Wait for all previous reads to complete since they are now
                // tracked on the wrong channel.  The WRO module only compares
                // addresses within a channel.  We don't want new writes to
                // commit before outstanding reads complete.
                if (num_outstanding_reads == 0)
                begin
                    block_tx_traffic <= 1'b0;

                    state <= CCI_MPF_VC_MAP_SAMPLING;
                end
            end
        endcase

        if (reset)
        begin
            state <= CCI_MPF_VC_MAP_SAMPLING;
            block_tx_traffic <= 1'b0;
            events.vc_map_out_event_mapping_changed <= 1'b0;
        end
    end

    // WrFence is emitted if requested and no C1 TX traffic is being
    // requested by the AFU.
    assign emit_wrfence_en =
        (state == CCI_MPF_VC_MAP_EMIT_WRFENCE) &&
        ! cci_mpf_c1TxIsValid(c1_tx) &&
        ! fiu.c0TxAlmFull;

    // WrFence response received?
    assign is_vc_map_wrfence_rsp =
        cci_c1Rx_isWriteFenceRsp(fiu.c1Rx) &&
        fiu.c1Rx.hdr.mdata[RESERVED_MDATA_IDX];

    typedef logic [MAX_SAMPLE_CYCLES_RADIX-1 : 0] t_sample_cnt;
    t_sample_cnt n_sampled_reads;
    t_sample_cnt n_sampled_writes;

    // reads + writes, hence larger counters
    logic [MAX_SAMPLE_CYCLES_RADIX : 0] n_sampled_len1;
    logic [MAX_SAMPLE_CYCLES_RADIX : 0] n_sampled_len2;
    logic [MAX_SAMPLE_CYCLES_RADIX : 0] n_sampled_len4;

    // Was a request on VA present?  No point in change unless there are some.
    logic saw_va_req;

    logic sample_region_done;
    logic sample_ready;

    t_map_ratio sample_suggestions[0 : N_SAMPLE_REGIONS-1];

    // Do all regions match?
    logic all_regions_match;
    always_comb
    begin
        all_regions_match = 1'b1;

        for (int i = 0; i < N_SAMPLE_REGIONS-1; i = i + 1)
        begin
            all_regions_match =
                all_regions_match &&
                (sample_suggestions[i + 1] == sample_suggestions[i]);
        end
    end

    //
    // Update ratio being used at sampling boundary.  The "damper" variable
    // limits the rate of change.
    //
    logic [5 : 0] damper;

    always_comb
    begin
        req_ratio_vl0_en = 1'b0;
        req_ratio_vl0 = 'x;

        if (sample_ready)
        begin
            if (all_regions_match)
            begin
                // In a consistent recommended state.  Change to it if not
                // there already.
                req_ratio_vl0_en = 1'b1;
                req_ratio_vl0 = sample_suggestions[0];
            end
            else
            begin
                // Not in a consistent state.  After waiting a while change
                // to the default state.
                req_ratio_vl0_en = damper[$bits(damper)-1];
                req_ratio_vl0 = RATIO_VL0_DEFAULT;
            end
        end
    end


    //
    // Reduce spurious change by damping reversion to the default ratio.
    //
    always_ff @(posedge clk)
    begin
        if (sample_ready)
        begin
            if (all_regions_match)
            begin
                // Matched a group of regions
                damper <= 0;
            end
            else if (! damper[$bits(damper)-1])
            begin
                // Variable recommendations found in successive regions.
                // Increment damper with a saturating counter.
                damper <= damper + 1;
            end
        end

        if (reset)
        begin
            damper <= 0;
        end
    end


    //
    // What is the typical number of lines per request in the current
    // sample interval?
    //
    function automatic t_ccip_clLen sampled_req_len();
        // Only claim length 1 if all traffic is 1
        if ((n_sampled_len2 == 0) && (n_sampled_len4 == 0))
        begin
            return eCL_LEN_1;
        end
        else if ((n_sampled_len4 >> 3) > n_sampled_len2)
        begin
            // len 4 is at least 8x more frequent than len 2
            return eCL_LEN_4;
        end
        else
        begin
            return eCL_LEN_2;
        end
    endfunction

    always_ff @(posedge clk)
    begin
        // Run once every time a region ends (based on clocks)
        if (sample_region_done && (state == CCI_MPF_VC_MAP_SAMPLING))
        begin
            // Shift old suggestions
            for (int i = 0; i < N_SAMPLE_REGIONS-1; i = i + 1)
            begin
                sample_suggestions[i + 1] <= sample_suggestions[i];
            end

            // Compute a new suggestion.
            //
            // Claim mostly reads or mostly writes only if one is at
            // least 8x more frequent than the other.
            sample_suggestions[0] <=
                pickRatioVL0((n_sampled_reads >> 3) > n_sampled_writes,
                             (n_sampled_writes >> 3) > n_sampled_reads,
                             sampled_req_len());

            sample_ready <= saw_va_req;
        end
        else
        begin
            sample_ready <= 1'b0;
        end

        if (reset)
        begin
            sample_ready <= 1'b0;
        end
    end


    // ====================================================================
    //
    //   Count reads and writes over sample interval.
    //
    // ====================================================================

    logic [MAX_SAMPLE_CYCLES_RADIX : 0] cycle_cnt;
    assign sample_region_done = (cycle_cnt[sample_interval_idx] == 1'b1);

    logic rd_len1;
    logic rd_len2;
    logic rd_len4;
    logic wr_len1;
    logic wr_len2;
    logic wr_len4;

    always_comb
    begin
        rd_len1 = 0;
        rd_len2 = 0;
        rd_len4 = 0;

        if (cci_mpf_c0TxIsReadReq(c0_tx))
        begin
            case (c0_tx.hdr.base.cl_len)
                eCL_LEN_1: rd_len1 = 1;
                eCL_LEN_2: rd_len2 = 1;
                  default: rd_len4 = 1;
            endcase
        end

        wr_len1 = 0;
        wr_len2 = 0;
        wr_len4 = 0;

        if (cci_mpf_c1TxIsWriteReq(c1_tx))
        begin
            case (c1_tx.hdr.base.cl_len)
                eCL_LEN_1: wr_len1 = 1;
                eCL_LEN_2: wr_len2 = 1;
                  default: wr_len4 = 1;
            endcase
        end
    end

    always_ff @(posedge clk)
    begin
        cycle_cnt <= cycle_cnt + 1;

        if (sample_region_done)
        begin
            // End of sampling interval.  Reset all counters.
            cycle_cnt <= 1'b1;

            n_sampled_reads <= 0;
            n_sampled_writes <= 0;
            n_sampled_len1 <= 0;
            n_sampled_len2 <= 0;
            n_sampled_len4 <= 0;
            saw_va_req <= 0;
        end
        else
        begin
            if (cci_mpf_c0TxIsReadReq(c0_tx))
            begin
                n_sampled_reads <= n_sampled_reads + 1;

                if (req_needs_mapping(c0_tx.hdr.base.vc_sel))
                begin
                    saw_va_req <= 1;
                end
            end

            if (cci_mpf_c1TxIsWriteReq(c1_tx))
            begin
                n_sampled_writes <= n_sampled_writes + 1;

                if (req_needs_mapping(c1_tx.hdr.base.vc_sel))
                begin
                    saw_va_req <= 1;
                end
            end

            n_sampled_len1 <= n_sampled_len1 + rd_len1 + wr_len1;
            n_sampled_len2 <= n_sampled_len2 + rd_len2 + wr_len2;
            n_sampled_len4 <= n_sampled_len4 + rd_len4 + wr_len4;
        end

        if (reset)
        begin
            cycle_cnt <= 0;

            n_sampled_reads <= 0;
            n_sampled_writes <= 0;
            n_sampled_len1 <= 0;
            n_sampled_len2 <= 0;
            n_sampled_len4 <= 0;
            saw_va_req <= 0;
        end
    end


    // ====================================================================
    // 
    //   Track outstanding reads
    // 
    // ====================================================================

    logic is_new_read_req;
    logic is_read_eop;

    assign is_new_read_req = cci_mpf_c0TxIsReadReq(c0_tx);
    assign is_read_eop = cci_mpf_c0Rx_isEOP(fiu.c0Rx);

    always_ff @(posedge clk)
    begin
        if (is_new_read_req && ! is_read_eop)
        begin
            num_outstanding_reads <= num_outstanding_reads + 1;
        end

        if (! is_new_read_req && is_read_eop)
        begin
            num_outstanding_reads <= num_outstanding_reads - 1;
        end

        if (reset)
        begin
            num_outstanding_reads <= 0;
        end
    end

endmodule // cci_mpf_shim_vc_map
