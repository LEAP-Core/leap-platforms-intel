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


//
// This is a mandatory connection at the head and tail of an MPF pipeline.
// It canonicalizes input and output and manages the flow of data through
// MPF.
//

module cci_mpf_shim_edge_connect
   (
    input  logic clk,

    // External connections to the FIU and AFU
    cci_mpf_if.to_fiu fiu_edge,
    cci_mpf_if.to_afu afu_edge,

    // Connection to the FIU end of the MPF pipeline
    cci_mpf_if.to_afu fiu,

    // Connection to the AFU end of the MPF pipeline
    cci_mpf_if.to_fiu afu
    );

    logic reset;
    assign reset = fiu_edge.reset;

    // Normal shims connect reset from FIU toward AFU.  This module has
    // two independent flows: the FIU edge and the AFU edge.  The MPF
    // pipeline will be the link between the two flows.  Hook up reset
    // independently.  The chain will be completed by the MPF pipeline.
    assign fiu.reset = fiu_edge.reset;
    assign afu_edge.reset = afu.reset;


    //
    // Save write data as it arrives from the AFU in a heap here.  Use
    // the saved values as requests exit MPF toward the FIU.  This has
    // multiple advantages:
    //
    //   - Internal buffer space inside MPF pipelines is greatly reduced
    //     since the wide request channel 1 data bus is eliminated.
    //
    //   - Multi-beat write requests are easier to handle.  The code
    //     here will send only one write request through MPF.  The remaining
    //     beats are saved in the heap here and regenerated when the
    //     control packet exits MPF.
    //
    localparam N_WRITE_HEAP_ENTRIES = 128;
    typedef logic [$clog2(N_WRITE_HEAP_ENTRIES)-1 : 0] t_write_heap_idx;

    logic wr_heap_not_full;
    t_write_heap_idx wr_heap_enq_idx;
    t_cci_clData wr_heap_data;

    logic wr_heap_deq_en;
    logic wr_heap_deq_en_q;
    t_write_heap_idx wr_heap_deq_idx;
    t_write_heap_idx wr_heap_deq_idx_q;

    // Dequeue delayed one cycle for timing
    always_ff @(posedge clk)
    begin
        wr_heap_deq_en_q <= wr_heap_deq_en;
        wr_heap_deq_idx_q <= wr_heap_deq_idx;
    end


    cci_mpf_prim_heap
      #(
        .N_ENTRIES(N_WRITE_HEAP_ENTRIES),
        .N_DATA_BITS(CCI_CLDATA_WIDTH),
        // Leave space both for the almost full threshold and a full
        // multi-line packet.  To avoid deadlocks we never signal a
        // transition to almost full in the middle of a packet so must
        // be prepared to absorb all flits.
        .MIN_FREE_SLOTS(CCI_TX_ALMOST_FULL_THRESHOLD +
                        CCI_MAX_MULTI_LINE_BEATS + 1),
        .N_OUTPUT_REG_STAGES(1)
        )
      wr_heap
       (
        .clk,
        .reset,

        // Add data to the heap as it arrives from the AFU
        .enq(cci_mpf_c1TxIsWriteReq(afu_edge.c1Tx)),
        .enqData(afu_edge.c1Tx.data),
        .notFull(wr_heap_not_full),
        .allocIdx(wr_heap_enq_idx),

        // Retrieve data as it leaves toward the FIU. The heap index
        // holding the write data is stored in the low bits of the request
        // field that would have held the data itself.
        .readReq(wr_heap_deq_idx),
        .readRsp(wr_heap_data),
        .free(wr_heap_deq_en_q),
        .freeIdx(wr_heap_deq_idx_q)
        );


    // ====================================================================
    //
    //   FIU edge flow
    //
    // ====================================================================

    // All but write requests flow straight through
    assign fiu_edge.c0Tx = cci_mpf_updC0TxCanonical(fiu.c0Tx);
    assign fiu_edge.c2Tx = fiu.c2Tx;

    assign fiu.c0TxAlmFull = fiu_edge.c0TxAlmFull;

    assign fiu.c0Rx = fiu_edge.c0Rx;
    assign fiu.c1Rx = fiu_edge.c1Rx;


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
    logic wr_heap_data_rdy;
    logic wr_req_may_fire;

    // Pipeline stages
    t_if_cci_mpf_c1_Tx stg1_fiu_c1Tx;
    t_if_cci_mpf_c1_Tx stg2_fiu_c1Tx;
    t_if_cci_mpf_c1_Tx stg3_fiu_c1Tx;

    always_comb
    begin
        wr_req_may_fire = ! fiu_edge.c1TxAlmFull && wr_heap_data_rdy;

        // Processing is complete when all beats have been emitted.
        stg1_packet_done = wr_req_may_fire && (stg1_fiu_wr_beats_rem == 0);

        // Read from the write data heap if there is a write request to process.
        wr_heap_deq_en = wr_req_may_fire && cci_mpf_c1TxIsWriteReq(stg1_fiu_c1Tx);

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

                wr_heap_data_rdy <= cci_mpf_c1TxIsValid(fiu_c1Tx_first);
                wr_heap_deq_idx <= t_write_heap_idx'(fiu_c1Tx_first.data);
            end
            else if (stg1_packet_done)
            begin
                // Pipeline is moving but no new request is available
                stg1_fiu_c1Tx <= cci_c1Tx_clearValids();
                wr_heap_data_rdy <= 1'b0;
            end
            else if (wr_heap_deq_en)
            begin
                // In the middle of a multi-beat request
                stg1_fiu_c1Tx_sop <= 1'b0;
                stg1_fiu_wr_beat_idx <= stg1_fiu_wr_beat_idx + 1;
                stg1_fiu_wr_beats_rem <= stg1_fiu_wr_beats_rem - 1;

                wr_heap_deq_idx <= wr_heap_deq_idx + 1;
                wr_heap_data_rdy <=
                    ((wr_heap_deq_idx + t_write_heap_idx'(1)) != wr_heap_enq_idx);
            end
            else
            begin
                wr_heap_data_rdy <=
                    cci_mpf_c1TxIsValid(stg1_fiu_c1Tx) &&
                    (wr_heap_deq_idx != wr_heap_enq_idx);
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
        fiu_edge.c1Tx = stg3_fiu_c1Tx;
        fiu_edge.c1Tx.data = wr_heap_data;
    end


    // ====================================================================
    //
    //   AFU edge flow
    //
    // ====================================================================

    logic afu_wr_packet_active;

    // All but write requests flow straight through
    assign afu.c0Tx = cci_mpf_updC0TxCanonical(afu_edge.c0Tx);
    assign afu.c2Tx = afu_edge.c2Tx;

    assign afu_edge.c0TxAlmFull = afu.c0TxAlmFull;
    // Never signal almost full in the middle of a packet. Deadlocks can result
    // since the control flit is already flowing through MPF.
    assign afu_edge.c1TxAlmFull = (afu.c1TxAlmFull || ! wr_heap_not_full) &&
                                  ! afu_wr_packet_active;

    assign afu_edge.c0Rx = afu.c0Rx;
    assign afu_edge.c1Rx = afu.c1Rx;

    always_comb
    begin
        afu.c1Tx = cci_mpf_updC1TxCanonical(afu_edge.c1Tx);

        // The cache line's value stored in afu.c1Tx.data is no longer needed
        // in the pipeline.  Store 'x but use the low bits to hold the
        // local heap index.
        afu.c1Tx.data = 'x;
        afu.c1Tx.data[$clog2(N_WRITE_HEAP_ENTRIES) - 1 : 0] = wr_heap_enq_idx;

        // Multi-beat write request?  Only the start of packet beat goes
        // through MPF.  The rest are buffered in wr_heap here and the
        // packets will be regenerated when the sop packet exits.
        afu.c1Tx.valid = afu_edge.c1Tx.valid &&
                         (afu_edge.c1Tx.hdr.base.sop ||
                          (afu_edge.c1Tx.hdr.base.cl_len == eCL_LEN_1));
    end


    //
    // Validate request.  All the remaining code is just validation that
    // multi-beat requests are formatted properly.
    //

    cci_mpf_prim_track_multi_write
      afu_wr_track
       (
        .clk,
        .reset,
        .c1Tx(afu_edge.c1Tx),
        .c1Tx_en(1'b1),
        .packetActive(afu_wr_packet_active),
        .nextBeatNum()
        );

    t_ccip_clAddr afu_wr_prev_addr;
    t_cci_clLen afu_wr_prev_cl_len;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            // Nothing
        end
        else
        begin
            if (cci_mpf_c0TxIsReadReq(afu_edge.c0Tx))
            begin
                assert((afu_edge.c0Tx.hdr.base.address[1:0] & afu_edge.c0Tx.hdr.base.cl_len) == 2'b0) else
                    $fatal("cci_mpf_shim_edge_connect: Multi-beat read address must be naturally aligned");
            end

            if (cci_mpf_c1TxIsWriteReq(afu_edge.c1Tx))
            begin
                assert(afu_edge.c1Tx.hdr.base.sop != afu_wr_packet_active) else
                    if (! afu_edge.c1Tx.hdr.base.sop)
                        $fatal("cci_mpf_shim_edge_connect: Expected SOP flag on write");
                    else
                        $fatal("cci_mpf_shim_edge_connect: Wrong number of multi-beat writes");

                if (afu_edge.c1Tx.hdr.base.sop)
                begin
                    assert ((afu_edge.c1Tx.hdr.base.address[1:0] & afu_edge.c1Tx.hdr.base.cl_len) == 2'b0) else
                        $fatal("cci_mpf_shim_edge_connect: Multi-beat write address must be naturally aligned");
                end
                else
                begin
                    assert (afu_wr_prev_cl_len == afu_edge.c1Tx.hdr.base.cl_len) else
                        $fatal("cci_mpf_shim_edge_connect: cl_len must be the same in all beats of a multi-line write");

                    assert ((afu_wr_prev_addr + 1) == afu_edge.c1Tx.hdr.base.address) else
                        $fatal("cci_mpf_shim_edge_connect: Address must increment with each beat in multi-line write");
                end

                afu_wr_prev_addr <= afu_edge.c1Tx.hdr.base.address;
                afu_wr_prev_cl_len <= afu_edge.c1Tx.hdr.base.cl_len;
            end
        end
    end

endmodule // cci_mpf_shim_edge_connect
