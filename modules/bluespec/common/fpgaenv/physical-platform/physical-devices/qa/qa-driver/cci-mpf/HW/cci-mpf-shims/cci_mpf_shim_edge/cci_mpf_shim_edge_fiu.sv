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
`include "cci_mpf_shim_edge.vh"

//
// This is a mandatory connection at the tail of an MPF pipeline.
// It canonicalizes input and output and manages the flow of data through
// MPF.
//

module cci_mpf_shim_edge_fiu
  #(
    parameter N_WRITE_HEAP_ENTRIES = 0,

    // The VTP page table walker needs to generate loads in order to read
    // the page table.  The reserved bit in Mdata is a location offered
    // to the page table walker to tag internal loads.  The Mdata location
    // must be zero on all requests flowing into this module through
    // the MPF pipeline.
    //
    // Some shims (e.g. cci_mpf_shim_sort_responses) already manage Mdata and
    // guarantee that some high bits will be zero.
    parameter VTP_PT_RESERVED_MDATA_IDX = -1
    )
   (
    input  logic clk,

    // External connection to the FIU
    cci_mpf_if.to_fiu fiu_ext,

    // Connection to the FIU end of the MPF pipeline
    cci_mpf_if.to_afu fiu,

    // Interface to the MPF AFU edge module
    cci_mpf_shim_edge_if.edge_fiu afu_edge,

    // Interface to the VTP page table walker.  The page table requests
    // host memory page table reads through this connection.
    cci_mpf_shim_vtp_pt_walk_if.mem_read pt_walk
    );

    logic reset;
    assign reset = fiu_ext.reset;
    assign fiu.reset = fiu_ext.reset;

    //
    // The AFU edge forwards write data to this module, routing the data
    // around the MPF pipeline.  The AFU edge manages the indices used
    // to store the data.  The data storage (block RAM) is here.
    //
    typedef logic [$clog2(N_WRITE_HEAP_ENTRIES)-1 : 0] t_write_heap_idx;

    logic wr_heap_deq_en;
    t_write_heap_idx wr_heap_deq_idx;
    t_cci_clNum wr_heap_deq_clNum;
    t_cci_clData wr_data;

    // Free slots once write exits
    always_ff @(posedge clk)
    begin
        afu_edge.free <= wr_heap_deq_en;
        afu_edge.freeidx <= wr_heap_deq_idx;
    end

    //
    // The true number of write heap entries is larger than
    // N_WRITE_HEAP_ENTRIES because only one logical slot is used, even
    // for multi-beat writes.  Multi-beat writes share a heap index and
    // the index and cl_num for a flit are concatenated to form the
    // data's heap address.
    //
    localparam N_UNIQUE_WRITE_HEAP_ENTRIES =
        N_WRITE_HEAP_ENTRIES * CCI_MAX_MULTI_LINE_BEATS;

    assign afu_edge.wrdy = 1'b1;

    // Heap data, addressed using the indices handed out by wr_heap_ctrl.
    cci_mpf_prim_ram_simple
      #(
        .N_ENTRIES(N_UNIQUE_WRITE_HEAP_ENTRIES),
        .N_DATA_BITS(CCI_CLDATA_WIDTH),
        .N_OUTPUT_REG_STAGES(1)
        )
      wr_heap_data
       (
        .clk,

        .wen(afu_edge.wen),
        .waddr({ afu_edge.widx, afu_edge.wclnum }),
        .wdata(afu_edge.wdata),

        .raddr({ wr_heap_deq_idx, wr_heap_deq_clNum }),
        .rdata(wr_data)
        );


    // ====================================================================
    //
    //   FIU edge flow
    //
    // ====================================================================

    //
    // Channel 0 (reads)
    //

    // Reads flow through undisturbed except for the need to inject reads
    // requested by the page table walker here.

    logic pt_walk_read_req;
    logic pt_walk_emit_req;
    t_cci_clAddr pt_walk_read_addr;

    assign pt_walk.readRdy = ! pt_walk_read_req;

    //
    // Track requests to read a line in the page table.
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            pt_walk_read_req <= 1'b0;
        end
        else
        begin
            // Either a request completed or a new one arrived
            pt_walk_read_req <= (pt_walk_read_req ^ pt_walk_emit_req) ||
                                pt_walk.readEn;
        end

        // Register requested address
        if (pt_walk.readEn)
        begin
            pt_walk_read_addr <= pt_walk.readAddr;
        end
    end

    // Stop traffic to make sure a slot for the walk request becomes available
    assign fiu.c0TxAlmFull = fiu_ext.c0TxAlmFull && ! pt_walk_read_req;

    // Emit the read for PT walk if a request is outstanding and there is
    // no request from the AFU.
    assign pt_walk_emit_req = pt_walk_read_req && ! cci_mpf_c0TxIsValid(fiu.c0Tx);

    // Request header for PT walk reads
    t_cci_mpf_c0_ReqMemHdr pt_walk_read_hdr;
    always_comb
    begin
        pt_walk_read_hdr = cci_mpf_c0_genReqHdr(eREQ_RDLINE_S,
                                                pt_walk_read_addr,
                                                t_cci_mdata'(0),
                                                cci_mpf_defaultReqHdrParams(0));
        pt_walk_read_hdr[VTP_PT_RESERVED_MDATA_IDX] = 1'b1;
    end

    //
    // Forward read requests
    //
    always_ff @(posedge clk)
    begin
        fiu_ext.c0Tx <= cci_mpf_updC0TxCanonical(fiu.c0Tx);

        if (pt_walk_emit_req)
        begin
            fiu_ext.c0Tx <= cci_mpf_genC0TxReadReq(pt_walk_read_hdr, 1'b1);
        end
    end

    // Is the read response for the page table walker?
    logic is_pt_rsp;
    always_comb
    begin
        is_pt_rsp = fiu.c0Rx.hdr[VTP_PT_RESERVED_MDATA_IDX];
        pt_walk.readDataEn = cci_c0Rx_isReadRsp(fiu_ext.c0Rx) && is_pt_rsp;
        pt_walk.readData = fiu_ext.c0Rx.data;
    end

    always_comb
    begin
        fiu.c0Rx = fiu_ext.c0Rx;

        // Only forward client-generated read responses
        fiu.c0Rx.rspValid = fiu_ext.c0Rx.rspValid && ! is_pt_rsp;
    end


    //
    // Channel 1 (writes)
    //

    // Responses
    assign fiu.c1Rx = fiu_ext.c1Rx;

    // Multi-beat writes complete by synthesizing new packets and reading
    // data from wr_heap.  c1 Tx flows through a buffering FIFO since
    // traffic has to stop when completing a multi-beat write.
    t_if_cci_mpf_c1_Tx fiu_c1Tx_first;
    logic fiu_c1Tx_deq;
    logic fiu_c1Tx_not_empty;

    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(t_if_cci_mpf_c1_Tx)),
        .N_ENTRIES(CCI_TX_ALMOST_FULL_THRESHOLD + 2),
        .THRESHOLD(CCI_TX_ALMOST_FULL_THRESHOLD)
        )
      fiu_c1Tx_fifo
       (
        .clk,
        .reset(reset),

        // The concatenated field order must match the use of c1_first above.
        .enq_data(cci_mpf_updC1TxCanonical(fiu.c1Tx)),
        .enq_en(fiu.c1Tx.valid),
        .notFull(),
        .almostFull(fiu.c1TxAlmFull),

        .first(fiu_c1Tx_first),
        .deq_en(fiu_c1Tx_deq),
        .notEmpty(fiu_c1Tx_not_empty)
        );


    //
    // Pick the next write request to forward.  Either the request is
    // a synthesized request to complete a multi-beat write or it is
    // a new request from the FIFO.
    //
    t_ccip_clNum stg1_fiu_wr_beat_idx;
    t_ccip_clNum stg1_fiu_wr_beats_rem;
    logic stg1_fiu_c1Tx_sop;
    logic stg1_packet_done;
    logic stg1_packet_is_new;
    logic stg1_flit_en;
    logic wr_req_may_fire;

    // Pipeline stages
    t_if_cci_mpf_c1_Tx stg1_fiu_c1Tx;
    t_if_cci_mpf_c1_Tx stg2_fiu_c1Tx;
    t_if_cci_mpf_c1_Tx stg3_fiu_c1Tx;

    always_comb
    begin
        wr_req_may_fire = ! fiu_ext.c1TxAlmFull;

        // Processing is complete when all beats have been emitted.
        stg1_packet_done = wr_req_may_fire && (stg1_fiu_wr_beats_rem == 0);

        // Ready to process a write flit?
        stg1_flit_en = wr_req_may_fire && cci_mpf_c1TxIsWriteReq(stg1_fiu_c1Tx);
        wr_heap_deq_clNum = stg1_fiu_wr_beat_idx;

        // Release the write data heap entry when a write retires
        wr_heap_deq_en = stg1_packet_done && cci_mpf_c1TxIsWriteReq(stg1_fiu_c1Tx);

        // Take the next request from the buffering FIFO when the current
        // packet is done or there is no packet being processed.
        fiu_c1Tx_deq = fiu_c1Tx_not_empty &&
                       (stg1_packet_done || ! cci_mpf_c1TxIsValid(stg1_fiu_c1Tx));
    end


    // Pipeline c1 Tx requests, waiting for heap data.
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            stg1_fiu_c1Tx_sop <= 1'b1;
            stg1_fiu_wr_beat_idx <= 1'b0;
            stg1_fiu_wr_beats_rem <= 1'b0;

            stg1_packet_is_new <= 1'b0;
            stg1_fiu_c1Tx <= cci_c1Tx_clearValids();
            stg2_fiu_c1Tx <= cci_c1Tx_clearValids();
            stg3_fiu_c1Tx <= cci_c1Tx_clearValids();
        end
        else
        begin
            stg1_packet_is_new <= fiu_c1Tx_deq;

            // Head of the pipeline
            if (fiu_c1Tx_deq)
            begin
                // Pipeline is moving and a new request is available
                stg1_fiu_c1Tx <= fiu_c1Tx_first;

                // The heap data for the SOP is definitely available
                // since it arrived with the header.
                stg1_fiu_c1Tx_sop <= 1'b1;
                stg1_fiu_wr_beat_idx <= 0;
                stg1_fiu_wr_beats_rem <= fiu_c1Tx_first.hdr.base.cl_len;

                wr_heap_deq_idx <= t_write_heap_idx'(fiu_c1Tx_first.data);
            end
            else if (stg1_packet_done)
            begin
                // Pipeline is moving but no new request is available
                stg1_fiu_c1Tx <= cci_c1Tx_clearValids();
            end
            else if (stg1_flit_en)
            begin
                // In the middle of a multi-beat request
                stg1_fiu_c1Tx_sop <= 1'b0;
                stg1_fiu_wr_beat_idx <= stg1_fiu_wr_beat_idx + 1;
                stg1_fiu_wr_beats_rem <= stg1_fiu_wr_beats_rem - 1;
            end

            if (wr_req_may_fire)
            begin
                // Write request this cycle
                stg2_fiu_c1Tx <= stg1_fiu_c1Tx;
                // SOP set only first first beat in a multi-beat packet
                stg2_fiu_c1Tx.hdr.base.sop <= stg1_fiu_c1Tx_sop;
                // Low bits of aligned address reflect the beat
                stg2_fiu_c1Tx.hdr.base.address[$bits(t_ccip_clNum)-1 : 0] <=
                    stg1_fiu_c1Tx.hdr.base.address[$bits(t_ccip_clNum)-1 : 0] |
                    stg1_fiu_wr_beat_idx;
            end
            else
            begin
                // Nothing starting this cycle
                stg2_fiu_c1Tx <= cci_c1Tx_clearValids();
            end

            stg3_fiu_c1Tx <= stg2_fiu_c1Tx;
        end
    end


    // Merge FIU-bound data with request
    always_comb
    begin
        fiu_ext.c1Tx = stg3_fiu_c1Tx;
        fiu_ext.c1Tx.data = wr_data;
    end


    //
    // Channel 2 (MMIO)
    //

    always_ff @(posedge clk)
    begin
        fiu_ext.c2Tx <= fiu.c2Tx;
    end


    //
    // Validate parameter settings and that the Mdata reserved bit is 0
    // on all incoming read requests.
    //
    always_ff @(posedge clk)
    begin
        assert ((VTP_PT_RESERVED_MDATA_IDX > 0) && (VTP_PT_RESERVED_MDATA_IDX < CCI_MDATA_WIDTH)) else
            $fatal("cci_mpf_shim_edge_fiu.sv: Illegal VTP_PT_RESERVED_MDATA_IDX value: %d", VTP_PT_RESERVED_MDATA_IDX);

        if (! reset)
        begin
            assert((fiu.c0Tx.hdr[VTP_PT_RESERVED_MDATA_IDX] == 0) ||
                   ! fiu.c0Tx.valid) else
                $fatal("cci_mpf_shim_edge_fiu.sv: AFU C0 Mdata[%d] must be zero", VTP_PT_RESERVED_MDATA_IDX);
        end
    end

endmodule // cci_mpf_shim_edge_fiu
