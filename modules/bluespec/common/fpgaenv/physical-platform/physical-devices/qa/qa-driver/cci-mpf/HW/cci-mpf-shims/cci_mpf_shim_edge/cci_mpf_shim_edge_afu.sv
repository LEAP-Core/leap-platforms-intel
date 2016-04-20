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
// This is a mandatory connection at the head of an MPF pipeline.
// It canonicalizes input and output and manages the flow of data through
// MPF.
//

module cci_mpf_shim_edge_afu
  #(
    parameter N_WRITE_HEAP_ENTRIES = 0
    )
   (
    input  logic clk,

    // Connection toward the FIU (the end of the MPF pipeline nearest the AFU)
    cci_mpf_if.to_fiu fiu,

    // External connections to the AFU
    cci_mpf_if.to_afu afu,

    // Interface to the MPF FIU edge module
    cci_mpf_shim_edge_if.edge_afu fiu_edge
    );

    logic reset;
    assign reset = fiu.reset;
    assign afu.reset = fiu.reset;


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
    typedef logic [$clog2(N_WRITE_HEAP_ENTRIES)-1 : 0] t_write_heap_idx;

    logic wr_heap_alloc;
    logic wr_heap_not_full;
    t_write_heap_idx wr_heap_enq_idx;
    t_cci_clNum wr_heap_enq_clNum;

    cci_mpf_prim_heap_ctrl
      #(
        .N_ENTRIES(N_WRITE_HEAP_ENTRIES),
        // Leave space both for the almost full threshold and a full
        // multi-line packet.  To avoid deadlocks we never signal a
        // transition to almost full in the middle of a packet so must
        // be prepared to absorb all flits.
        .MIN_FREE_SLOTS(CCI_TX_ALMOST_FULL_THRESHOLD +
                        CCI_MAX_MULTI_LINE_BEATS + 1)
        )
      wr_heap_ctrl
       (
        .clk,
        .reset,

        // Add entries to the heap as writes arrive from the AFU
        .enq(wr_heap_alloc),
        .notFull(wr_heap_not_full),
        .allocIdx(wr_heap_enq_idx),

        // Free entries as writes leave toward the FIU.
        .free(fiu_edge.free),
        .freeIdx(fiu_edge.freeidx)
        );


    //
    // The heap holding write data is in the FIU edge module.
    //
    assign fiu_edge.wen = cci_mpf_c1TxIsWriteReq(afu.c1Tx);
    assign fiu_edge.widx = wr_heap_enq_idx;
    assign fiu_edge.wclnum = wr_heap_enq_clNum;
    assign fiu_edge.wdata = afu.c1Tx.data;


    // ====================================================================
    //
    //   AFU edge flow
    //
    // ====================================================================

    logic afu_wr_packet_active;
    logic afu_wr_sticky_full;
    logic afu_wr_eop;

    assign wr_heap_alloc = cci_mpf_c1TxIsWriteReq(afu.c1Tx) && afu_wr_eop;

    logic afu_wr_almost_full;
    assign afu_wr_almost_full = fiu.c1TxAlmFull || ! wr_heap_not_full;

    // All but write requests flow straight through
    assign fiu.c0Tx = cci_mpf_updC0TxCanonical(afu.c0Tx);
    assign fiu.c2Tx = afu.c2Tx;

    //
    // Register almost full signals before they reach the AFU.  MPF modules
    // must accommodate the extra cycle of buffering that may be needed
    // as a result of signalling almost full a cycle late.
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            afu.c0TxAlmFull <= 1'b1;
            afu.c1TxAlmFull <= 1'b1;
            afu_wr_sticky_full <= 1'b0;
        end
        else
        begin
            afu.c0TxAlmFull <= fiu.c0TxAlmFull;

            // Never signal almost full in the middle of a packet. Deadlocks
            // can result since the control flit is already flowing through MPF.
            afu.c1TxAlmFull <= afu_wr_almost_full &&
                                   (! afu_wr_packet_active || afu_wr_sticky_full);

            // afu_wr_sticky_full goes high as soon as afu_wr_almost_full is
            // asserted and no packet is in flight.  It stays high until
            // afu_wr_almost_full is no longer asserted.
            if (! afu_wr_almost_full)
            begin
                afu_wr_sticky_full <= 1'b0;
            end
            else if (afu_wr_almost_full && ! afu_wr_packet_active)
            begin
                afu_wr_sticky_full <= 1'b1;
            end
        end
    end

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;

    always_comb
    begin
        fiu.c1Tx = cci_mpf_updC1TxCanonical(afu.c1Tx);

        // The cache line's value stored in fiu.c1Tx.data is no longer needed
        // in the pipeline.  Store 'x but use the low bits to hold the
        // local heap index.
        fiu.c1Tx.data = 'x;
        fiu.c1Tx.data[$clog2(N_WRITE_HEAP_ENTRIES) - 1 : 0] = wr_heap_enq_idx;

        // Multi-beat write request?  Only the start of packet beat goes
        // through MPF.  The rest are buffered in wr_heap here and the
        // packets will be regenerated when the sop packet exits.
        //
        // Only pass requests that are either the end of a write or
        // that aren't writes.
        if (cci_mpf_c1TxIsWriteReq_noCheckValid(afu.c1Tx))
        begin
            // Wait for the final flit to arrive and be buffered, thus
            // guaranteeing that all the data is ready to be written
            // as the packet exits to the FIU.
            fiu.c1Tx.valid = afu.c1Tx.valid &&
                             (wr_heap_enq_clNum == afu.c1Tx.hdr.base.cl_len);

            // Revert the address to the start of packet address
            fiu.c1Tx.hdr.base.sop = 1'b1;
            fiu.c1Tx.hdr.base.address[1:0] = afu.c1Tx.hdr.base.address[1:0] ^
                                             afu.c1Tx.hdr.base.cl_len;
        end
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
        .c1Tx(afu.c1Tx),
        .c1Tx_en(1'b1),
        .eop(afu_wr_eop),
        .packetActive(afu_wr_packet_active),
        .nextBeatNum(wr_heap_enq_clNum)
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
            if (cci_mpf_c0TxIsReadReq(afu.c0Tx))
            begin
                assert((afu.c0Tx.hdr.base.address[1:0] & afu.c0Tx.hdr.base.cl_len) == 2'b0) else
                    $fatal("cci_mpf_shim_edge_connect: Multi-beat read address must be naturally aligned");
            end

            if (cci_mpf_c1TxIsWriteReq(afu.c1Tx))
            begin
                assert(afu.c1Tx.hdr.base.sop != afu_wr_packet_active) else
                    if (! afu.c1Tx.hdr.base.sop)
                        $fatal("cci_mpf_shim_edge_connect: Expected SOP flag on write");
                    else
                        $fatal("cci_mpf_shim_edge_connect: Wrong number of multi-beat writes");

                if (afu.c1Tx.hdr.base.sop)
                begin
                    assert ((afu.c1Tx.hdr.base.address[1:0] & afu.c1Tx.hdr.base.cl_len) == 2'b0) else
                        $fatal("cci_mpf_shim_edge_connect: Multi-beat write address must be naturally aligned");
                end
                else
                begin
                    assert (afu_wr_prev_cl_len == afu.c1Tx.hdr.base.cl_len) else
                        $fatal("cci_mpf_shim_edge_connect: cl_len must be the same in all beats of a multi-line write");

                    assert ((afu_wr_prev_addr + 1) == afu.c1Tx.hdr.base.address) else
                        $fatal("cci_mpf_shim_edge_connect: Address must increment with each beat in multi-line write");
                end

                afu_wr_prev_addr <= afu.c1Tx.hdr.base.address;
                afu_wr_prev_cl_len <= afu.c1Tx.hdr.base.cl_len;
            end
        end
    end

endmodule // cci_mpf_shim_edge_afu

