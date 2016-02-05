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
`include "cci_mpf_prim_hash.vh"


//
// Guarantee that writes to the same address complete in order and that reads
// to addresses matching writes complete in order relative to the write.
//


module cci_mpf_shim_wro
  #(
    // Size of the incoming buffer.  It must be at least as large as the
    // almost full threshold.
    parameter N_AFU_BUF_ENTRIES = CCI_TX_ALMOST_FULL_THRESHOLD + 2
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu
    );

    logic reset;
    assign reset = fiu.reset;

    // ====================================================================
    //
    //  Characteristics of the filters.
    //
    // ====================================================================

    // Number of reads or writes permitted in flight is a function of the
    // index space.  C0 is the read request channel and C1 is the write
    // request channel.  Often more reads must be in flight than writes
    // for full throughput.
    localparam N_C0_CAM_IDX_ENTRIES = 80;
    localparam N_C1_CAM_IDX_ENTRIES = 48;

    // Size of an address hash entry. Smaller sizes take less space but
    // increase the probability of address collisions.
    localparam ADDRESS_HASH_BITS = 9;


    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    cci_mpf_if
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic afu_deq;
    logic addr_conflict_incoming;

    cci_mpf_shim_buffer_lockstep_afu
      #(
        .N_ENTRIES(N_AFU_BUF_ENTRIES),
        .THRESHOLD(CCI_TX_ALMOST_FULL_THRESHOLD)
        )
      bufafu
       (
        .clk,
        .afu_raw(afu),
        .afu_buf(afu_buf),
        .deqTx(afu_deq)
        );

    assign afu_buf.reset = fiu.reset;

    //
    // Almost full signals in the buffered input are ignored --
    // replaced by deq signals and the buffer state.  Set them
    // to 1 to be sure they are ignored.
    //
    assign afu_buf.c0TxAlmFull = 1'b1;
    assign afu_buf.c1TxAlmFull = 1'b1;


    // ====================================================================
    //
    //  Instantiate a buffer on the FIU response port to give time to
    //  read local state in block RAMs before forwarding the response
    //  toward the AFU.
    //
    // ====================================================================

    cci_mpf_if
      fiu_buf (.clk);

    cci_mpf_shim_buffer_fiu
      #(
        // Add a register on output for timing
        .REGISTER_OUTBOUND(1)
        )
      buffiu
       (
        .clk,
        .fiu_raw(fiu),
        .fiu_buf(fiu_buf)
        );


    // ====================================================================
    //
    //  Incoming requests.
    //
    // ====================================================================

    //
    // Hash addresses into smaller values to reduce storage and comparison
    // overhead.
    //
    
    typedef logic [ADDRESS_HASH_BITS-1 : 0] t_HASH;

    t_HASH c0_hash_calc;
    t_HASH c1_hash_calc;

    // Start by expanding the addresses to 64 bits.  The hash is computed
    // on the way in to the afu_buf and stored in a FIFO the same size
    // as the buffer in order to reduce timing pressure at the point the
    // filter is checked and updated.
    logic [63:0] c0_req_addr;
    assign c0_req_addr = 64'(cci_mpf_c0_getReqAddr(afu_buf.c0Tx.hdr));

    logic [63:0] c1_req_addr;
    assign c1_req_addr = 64'(cci_mpf_c1_getReqAddr(afu_buf.c1Tx.hdr));

    assign c0_hash_calc =
        t_HASH'(hash32(c0_req_addr[63:32] ^ c0_req_addr[31:0]));
    assign c1_hash_calc =
        t_HASH'(hash32(c1_req_addr[63:32] ^ c1_req_addr[31:0]));


    // ====================================================================
    //
    //  Filter to track busy addresses.
    //
    // ====================================================================

    typedef logic [$clog2(N_C0_CAM_IDX_ENTRIES)-1 : 0] t_C0_REQ_IDX;
    typedef logic [$clog2(N_C1_CAM_IDX_ENTRIES)-1 : 0] t_C1_REQ_IDX;

    // There are two sets of filters: one for reads and one for writes.
    // They are separate because multiple reads can be outstanding to
    // a single address but only one write may be live. New read requests
    // check only that there is no conflicting write.
    logic         rd_filter_test_notPresent;
    // New write requests check both that there is no conflicting write
    // and no conflicting read.
    logic [0 : 1] wr_filter_test_notPresent;

    // One hash for each request channel
    t_HASH [0 : 1] filter_test_req;
    logic  [0 : 1] filter_test_req_en;

    // Insert lines for entering new active reads and writes in the filter.
    // One for each channel.
    t_C0_REQ_IDX rd_filter_insert_idx;
    t_HASH       rd_filter_insert_hash;

    t_C1_REQ_IDX wr_filter_insert_idx;
    t_HASH       wr_filter_insert_hash;

    // Read response handling on channel 0.
    t_C0_REQ_IDX [0 : 0] rd_filter_remove_idx;
    logic        [0 : 0] rd_filter_remove_en;

    // Write responses arrive on both response channels.
    t_C1_REQ_IDX [0 : 0] wr_filter_remove_idx;
    logic        [0 : 0] wr_filter_remove_en;

    //
    // Generate the read and write filters.
    //
    cci_mpf_prim_filter_cam
      #(
        .N_BUCKETS(N_C0_CAM_IDX_ENTRIES),
        .BITS_PER_BUCKET(ADDRESS_HASH_BITS),
        .N_TEST_CLIENTS(1),
        .N_REMOVE_CLIENTS(1),
        .BYPASS_INSERT_TO_TEST(1)
        )
      rdFilter(.clk,
               .reset,
               // Only the write request channel checks against outstanding
               // reads. Multiple reads to the same address may be in flight
               // at the same time.
               .test_value(filter_test_req[1]),
               .test_en(filter_test_req_en[1]),
               .test_notPresent(),
               .test_notPresent_q(rd_filter_test_notPresent),
               .insert_idx(rd_filter_insert_idx),
               .insert_value(rd_filter_insert_hash),
               .insert_en(cci_mpf_c0TxIsReadReq(fiu_buf.c0Tx)),
               .remove_idx(rd_filter_remove_idx),
               .remove_en(rd_filter_remove_en));

    cci_mpf_prim_filter_cam
      #(
        .N_BUCKETS(N_C1_CAM_IDX_ENTRIES),
        .BITS_PER_BUCKET(ADDRESS_HASH_BITS),
        .N_TEST_CLIENTS(2),
        .N_REMOVE_CLIENTS(1),
        .BYPASS_INSERT_TO_TEST(1)
        )
      wrFilter(.clk,
               .reset,
               .test_value(filter_test_req),
               .test_en(filter_test_req_en),
               .test_notPresent(),
               .test_notPresent_q(wr_filter_test_notPresent),
               .insert_idx(wr_filter_insert_idx),
               .insert_value(wr_filter_insert_hash),
               .insert_en(cci_mpf_c1TxIsWriteReq(fiu_buf.c1Tx)),
               .remove_idx(wr_filter_remove_idx),
               .remove_en(wr_filter_remove_en));


    // Hold the hashed address associated with the buffered test result.
    // This is used only in assertions below and should be dropped
    // during dead code elimination when synthesized.
    t_HASH [0 : 1] filter_verify_req;
    logic  [0 : 1] filter_verify_req_en;

    always_ff @(posedge clk)
    begin
        filter_verify_req <= filter_test_req;
        filter_verify_req_en <= filter_test_req_en;
    end


    // ====================================================================
    //
    //  Heaps to hold old Mdata
    //
    // ====================================================================

    typedef struct packed
    {
        // Save the part of the request's Mdata that is overwritten by the
        // heap index.
        t_C0_REQ_IDX mdata;
    }
    t_C0_HEAP_ENTRY;

    t_C0_HEAP_ENTRY c0_heap_enqData;
    t_C0_REQ_IDX c0_heap_allocIdx;

    logic c0_heap_notFull;

    t_C0_REQ_IDX c0_heap_readReq;
    t_C0_HEAP_ENTRY c0_heap_readRsp;

    logic c0_heap_free;
    t_C0_REQ_IDX c0_heap_freeIdx;

    cci_mpf_prim_heap
      #(
        .N_ENTRIES(N_C0_CAM_IDX_ENTRIES),
        .N_DATA_BITS($bits(t_C0_HEAP_ENTRY))
        )
      c0_heap(.clk,
              .reset,
              .enq(cci_mpf_c0TxIsReadReq(fiu_buf.c0Tx)),
              .enqData(c0_heap_enqData),
              .notFull(c0_heap_notFull),
              .allocIdx(c0_heap_allocIdx),
              .readReq(c0_heap_readReq),
              .readRsp(c0_heap_readRsp),
              .free(c0_heap_free),
              .freeIdx(c0_heap_freeIdx)
              );


    //
    // The channel 1 (write request) heap.
    //

    typedef struct packed
    {
        // Save the part of the request's Mdata that is overwritten by the
        // heap index.
        t_C1_REQ_IDX mdata;
    }
    t_C1_HEAP_ENTRY;

    t_C1_HEAP_ENTRY c1_heap_enqData;
    t_C1_REQ_IDX c1_heap_allocIdx;

    logic c1_heap_notFull;

    t_C1_REQ_IDX c1_heap_readReq;
    t_C1_HEAP_ENTRY c1_heap_readRsp;

    logic c1_heap_free;
    t_C1_REQ_IDX c1_heap_freeIdx;

    cci_mpf_prim_heap
      #(
        .N_ENTRIES(N_C1_CAM_IDX_ENTRIES),
        .N_DATA_BITS($bits(t_C1_HEAP_ENTRY))
        )
      c1_heap(.clk,
              .reset,
              .enq(cci_mpf_c1TxIsWriteReq(fiu_buf.c1Tx)),
              .enqData(c1_heap_enqData),
              .notFull(c1_heap_notFull),
              .allocIdx(c1_heap_allocIdx),
              .readReq(c1_heap_readReq),
              .readRsp(c1_heap_readRsp),
              .free(c1_heap_free),
              .freeIdx(c1_heap_freeIdx)
              );


    //
    // Update the read and write filters as responses are processed.
    //
    assign rd_filter_remove_idx[0] = c0_heap_freeIdx;
    assign rd_filter_remove_en[0]  = c0_heap_free;

    assign wr_filter_remove_idx[0] = c1_heap_freeIdx;
    assign wr_filter_remove_en[0]  = c1_heap_free;


    // ====================================================================
    //
    //  Filtering pipeline
    //
    // ====================================================================

    //
    // Request data flowing through filtering pipeline
    //
    typedef struct packed
    {
        t_if_cci_mpf_c0_Tx c0Tx;
        t_HASH             c0AddrHash;

        t_if_cci_mpf_c1_Tx c1Tx;
        t_HASH             c1AddrHash;
    }
    t_REQUEST_PIPE;

    // Pipeline stage storage
    localparam AFU_PIPE_DEPTH = 2;
    t_REQUEST_PIPE afu_pipe[0 : AFU_PIPE_DEPTH-1];

    //
    // Work backwards in the pipeline.  First decide whether the oldest
    // request can fire.  If it can (or there is no request) then younger
    // requests will ripple through the pipeline.
    //

    // Is either AFU making a request?
    logic c0_request_rdy;
    assign c0_request_rdy = cci_mpf_c0TxIsValid(afu_pipe[1].c0Tx);

    logic c1_request_rdy;
    assign c1_request_rdy = cci_mpf_c1TxIsValid(afu_pipe[1].c1Tx);

    // Does the request want order to be enforced?
    logic c0_enforce_order;
    assign c0_enforce_order = cci_mpf_c0_getReqCheckOrder(afu_pipe[1].c0Tx.hdr);
    logic c1_enforce_order;
    assign c1_enforce_order = cci_mpf_c1_getReqCheckOrder(afu_pipe[1].c1Tx.hdr);

    // Was the request pipeline stalled last cycle?  If yes then the
    // filter is a function of the request at the end of the afu_pipe.
    // If it was not blocked then the filter is a function of an
    // earlier stage in the pipeline.  We have this stage for timing
    // despite the complexity it adds.
    logic was_blocked;

    // A pipeline bubble must be inserted every time was_blocked changes
    // in order for the tested filter test to catch up due to the
    // use of registers to break the test across cycles.
    logic pipeline_bubble;

    //
    // Compute whether new requests can be inserted into the filters.
    // c0 is read requests, c1 is write requests.
    //
    logic c0_filter_may_insert;
    assign c0_filter_may_insert = wr_filter_test_notPresent[0] ||
                                  ! c0_enforce_order;

    logic c1_filter_may_insert;
    assign c1_filter_may_insert = (rd_filter_test_notPresent &&
                                   wr_filter_test_notPresent[1]) ||
                                  ! c1_enforce_order;

    // Is a request blocked by inability to forward it to the FIU or a
    // conflict?
    logic c0_blocked;
    assign c0_blocked = c0_request_rdy &&
                        (fiu_buf.c0TxAlmFull ||
                         ! c0_heap_notFull ||
                         ! c0_filter_may_insert);

    logic c1_blocked;
    assign c1_blocked = c1_request_rdy &&
                        (fiu_buf.c1TxAlmFull ||
                         ! c1_heap_notFull ||
                         ! c1_filter_may_insert);

    // Process requests if one exists on either channel AND neither channel
    // is blocked.  The requirement that neither channel be blocked keeps
    // the two channels synchronized with respect to each other so that
    // read and write requests stay ordered relative to each other.
    logic process_requests;
    assign process_requests = (c0_request_rdy || c1_request_rdy) &&
                              ! (c0_blocked || c1_blocked) &&
                              ! pipeline_bubble;

    // Set the hashed value to insert in the filter when requests are
    // processed.
    assign rd_filter_insert_hash = afu_pipe[1].c0AddrHash;
    assign rd_filter_insert_idx = c0_heap_allocIdx;
    assign wr_filter_insert_hash = afu_pipe[1].c1AddrHash;
    assign wr_filter_insert_idx = c1_heap_allocIdx;

    //
    // Now that we know whether the oldest request was processed we can
    // manage flow through the pipeline.
    //

    // Advance if the oldest request was processed or the last stage is empty.
    logic advance_pipeline;
    assign advance_pipeline = ((process_requests && ! was_blocked) ||
                               ! (c0_request_rdy || c1_request_rdy));

    // Is the incoming pipeline moving?
    assign afu_deq = advance_pipeline &&
                     ! addr_conflict_incoming &&
                     (cci_mpf_c0TxIsValid(afu_buf.c0Tx) ||
                      cci_mpf_c1TxIsValid(afu_buf.c1Tx));

    // Does an incoming request have read and write to the same address?
    // Special case: delay the write.
    logic handled_addr_conflict;
    assign addr_conflict_incoming = cci_mpf_c0TxIsReadReq(afu_buf.c0Tx) &&
                                    cci_mpf_c1TxIsWriteReq(afu_buf.c1Tx) &&
                                    (c0_req_addr == c1_req_addr) &&
                                    ! handled_addr_conflict;

    // Update the pipeline
    t_REQUEST_PIPE afu_pipe_init;
    logic swap_entries;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            for (int i = 0; i < AFU_PIPE_DEPTH; i = i + 1)
            begin
                afu_pipe[i].c0Tx <= cci_mpf_c0Tx_clearValids();
                afu_pipe[i].c1Tx <= cci_mpf_c1Tx_clearValids();
            end

            handled_addr_conflict <= 0;
        end
        else
        begin
            if (advance_pipeline)
            begin
                afu_pipe[1] <= afu_pipe[0];
                afu_pipe[0] <= afu_pipe_init;

                // Remember whether there was an address conflict.  If there
                // was then the read has already been processed.
                handled_addr_conflict <= addr_conflict_incoming;
            end
            else if (swap_entries)
            begin
                // Oldest was blocked.  Try moving a newer entry around the
                // oldest.  They have been proven to be independent.
                afu_pipe[1] <= afu_pipe[0];
                afu_pipe[0] <= afu_pipe[1];
            end
            else if (process_requests)
            begin
                // Pipeline restarted after a bubble. Drop the request
                // that left the pipeline but don't advance yet so the
                // filter pipeline can catch up.
                afu_pipe[1].c0Tx <= cci_mpf_c0Tx_clearValids();
                afu_pipe[1].c1Tx <= cci_mpf_c1Tx_clearValids();
            end
        end
    end

    always_comb
    begin
        afu_pipe_init.c0Tx = afu_buf.c0Tx;
        if (cci_mpf_c0TxIsReadReq(afu_buf.c0Tx) && handled_addr_conflict)
        begin
            afu_pipe_init.c0Tx.valid = 1'b0;
        end
        afu_pipe_init.c0AddrHash = c0_hash_calc;

        afu_pipe_init.c1Tx = afu_buf.c1Tx;
        // Process write later if it conflicts with the read.
        if (addr_conflict_incoming)
        begin
            afu_pipe_init.c1Tx.valid = 1'b0;
        end
        afu_pipe_init.c1AddrHash = c1_hash_calc;
    end

    //
    // Calculate whether the entries in the afu_pipe can be swapped when
    // the oldest one is blocked.  Allowing a swap allows newer requests to
    // flow around blocked older requests.  The computation takes too long
    // to be used to affect pipeline flow combinationally, so it is computed
    // for use in the next cycle.
    //
    logic can_swap_oldest;

    // Record conflicts.  There are AFU_PIPE_DEPTH+1 conflict bits because
    // we must also compare against requests currently in afu_buf,
    // which by the cycle that can_swap_oldest is used may be in afu_pipe.
    logic [AFU_PIPE_DEPTH : 0] wr_wr_conflict;
    logic [AFU_PIPE_DEPTH : 0] wr_rd_conflict;

    always_ff @(posedge clk)
    begin
        // Can swap if there are no conflicts
        can_swap_oldest <= ! (|(wr_wr_conflict) || |(wr_rd_conflict));
    end

    always_comb
    begin
        //
        // Look for address matches that would make it illegal to rotate the
        // pipeline without inducing a conflict.
        //
        for (int i = 0; i < AFU_PIPE_DEPTH; i = i + 1)
        begin
            wr_wr_conflict[i] = 1'b0;
            wr_rd_conflict[i] = 1'b0;

            if (cci_mpf_c1TxIsWriteReq(afu_pipe[i].c1Tx))
            begin
                // Compare all writes against all other writes
                for (int j = i + 1; j < AFU_PIPE_DEPTH; j = j + 1)
                begin
                    wr_wr_conflict[i] =
                        wr_wr_conflict[i] ||
                        (cci_mpf_c1TxIsWriteReq(afu_pipe[j].c1Tx) &&
                         (afu_pipe[i].c1AddrHash == afu_pipe[j].c1AddrHash));
                end

                // Compare all writes against all other reads
                for (int j = 0; j < AFU_PIPE_DEPTH; j = j + 1)
                begin
                    wr_rd_conflict[i] =
                        wr_rd_conflict[i] ||
                        (cci_mpf_c0TxIsReadReq(afu_pipe[j].c0Tx) &&
                         (afu_pipe[i].c1AddrHash == afu_pipe[j].c0AddrHash));
                end
            end
        end

        //
        // Do the same checks for incoming requests from afu_buf in case
        // requests there enter afu_pipe this cycle.
        //

        // Incoming write against all other writes and reads
        wr_wr_conflict[AFU_PIPE_DEPTH] = 1'b0;
        if (cci_mpf_c1TxIsWriteReq(afu_buf.c1Tx))
        begin
            for (int i = 0; i < AFU_PIPE_DEPTH; i = i + 1)
            begin
                wr_wr_conflict[AFU_PIPE_DEPTH] =
                    wr_wr_conflict[AFU_PIPE_DEPTH] ||
                    (cci_mpf_c1TxIsWriteReq(afu_pipe[i].c1Tx) &&
                     (c1_hash_calc == afu_pipe[i].c1AddrHash)) ||
                    (cci_mpf_c0TxIsReadReq(afu_pipe[i].c0Tx) &&
                     (c1_hash_calc == afu_pipe[i].c0AddrHash));
            end
        end

        // Incoming read against all other writes
        wr_rd_conflict[AFU_PIPE_DEPTH] = 1'b0;
        if (cci_mpf_c0TxIsReadReq(afu_buf.c0Tx))
        begin
            for (int i = 0; i < AFU_PIPE_DEPTH; i = i + 1)
            begin
                wr_rd_conflict[AFU_PIPE_DEPTH] =
                    wr_rd_conflict[AFU_PIPE_DEPTH] ||
                    (cci_mpf_c1TxIsWriteReq(afu_pipe[i].c1Tx) &&
                     (c0_hash_calc == afu_pipe[i].c1AddrHash));
            end
        end
    end


    //
    // Update the addresses being tested in the filter.  The test value
    // for the filter is stored in a register.  Combinational logic could
    // be used but it would add a mux to the head of the already expensive
    // filter.
    //

    // If the pipeline is about to block try swapping the entries to avoid
    // blocking.
    assign swap_entries = (c0_blocked || c1_blocked) && can_swap_oldest &&
                          ! was_blocked;

    logic blocked_next;
    assign blocked_next = (c0_blocked || c1_blocked) && ! can_swap_oldest;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            filter_test_req_en <= 0;
            was_blocked <= 0;
            pipeline_bubble <= 0;
        end
        else
        begin
            if (blocked_next)
            begin
                // The pipeline advanced beyond the current test.  Restore
                // the test of the blocked request.
                filter_test_req[0] <= afu_pipe[1].c0AddrHash;
                filter_test_req[1] <= afu_pipe[1].c1AddrHash;

                filter_test_req_en[0] <= cci_mpf_c0TxIsReadReq(afu_pipe[1].c0Tx);
                filter_test_req_en[1] <= cci_mpf_c1TxIsWriteReq(afu_pipe[1].c1Tx);
            end
            else if (was_blocked)
            begin
                // The pipeline was blocked by the filter in the previous
                // cycle.  Now that the flow is resuming test the next
                // value, already stored in the first stage of the pipeline.
                filter_test_req[0] <= afu_pipe[0].c0AddrHash;
                filter_test_req[1] <= afu_pipe[0].c1AddrHash;

                filter_test_req_en[0] <= cci_mpf_c0TxIsReadReq(afu_pipe[0].c0Tx);
                filter_test_req_en[1] <= cci_mpf_c1TxIsWriteReq(afu_pipe[0].c1Tx);
            end
            else if (swap_entries)
            begin
                // The oldest entry is moving to the position of the newest.
                // Put its filtering request back in the pipeline.
                filter_test_req[0] <= afu_pipe[1].c0AddrHash;
                filter_test_req[1] <= afu_pipe[1].c1AddrHash;

                filter_test_req_en[0] <= cci_mpf_c0TxIsReadReq(afu_pipe[1].c0Tx);
                filter_test_req_en[1] <= cci_mpf_c1TxIsWriteReq(afu_pipe[1].c1Tx);
            end
            else
            begin
                // Normal, pipelined flow.  Next cycle we will test the value
                // being written to the first stage of the pipeline.
                filter_test_req[0] <= c0_hash_calc;
                filter_test_req[1] <= c1_hash_calc;

                filter_test_req_en[0] <= cci_mpf_c0TxIsReadReq(afu_buf.c0Tx) &
                                         ! handled_addr_conflict;
                filter_test_req_en[1] <= cci_mpf_c1TxIsWriteReq(afu_buf.c1Tx) &
                                         ! addr_conflict_incoming;
            end

            // Remember whether pipeline was blocked and whether a pipeline
            // bubble must be inserted due to a change in filter test source.
            pipeline_bubble <= (! was_blocked && blocked_next);
            was_blocked <= blocked_next;

            //
            // This pipeline has complicated control flow.  Confirm that
            // decisions made this cycle were based on the correct addresses.
            //
            if (process_requests)
            begin
                assert ((filter_verify_req[0] == afu_pipe[1].c0AddrHash) &&
                        (filter_verify_req[1] == afu_pipe[1].c1AddrHash) &&
                        (filter_verify_req_en[0] == cci_mpf_c0TxIsReadReq(afu_pipe[1].c0Tx)) &&
                        (filter_verify_req_en[1] == cci_mpf_c1TxIsWriteReq(afu_pipe[1].c1Tx))) else
                    $fatal("cci_mpf_shim_wro: Incorrect pipeline control");
            end
        end
    end


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    // Forward requests toward the FIU.  Replace part of the Mdata entry
    // with the scoreboard index.  The original Mdata is saved in the
    // heap and restored when the response is returned.
    always_comb
    begin
        fiu_buf.c0Tx = afu_pipe[1].c0Tx;
        fiu_buf.c0Tx.hdr.base.mdata[$bits(c0_heap_allocIdx)-1 : 0] = c0_heap_allocIdx;
        fiu_buf.c0Tx.valid = process_requests && c0_request_rdy;
    end

    // Save state that will be used when the response is returned.
    assign c0_heap_enqData.mdata = t_C0_REQ_IDX'(afu_pipe[1].c0Tx.hdr.base.mdata);

    // Request heap read as fiu responses arrive.  The heap's value will be
    // available the cycle fiu_buf is read.
    assign c0_heap_readReq = t_C0_REQ_IDX'(fiu.c0Rx.hdr);

    // Free heap entries as read responses arrive.
    assign c0_heap_freeIdx = t_C0_REQ_IDX'(fiu.c0Rx.hdr);
    assign c0_heap_free = cci_c0Rx_isReadRsp(fiu.c0Rx);

    // Either forward the header from the FIU for non-read responses or
    // reconstruct the read response header.
    always_comb
    begin
        afu_buf.c0Rx = fiu_buf.c0Rx;

        if (cci_c0Rx_isReadRsp(fiu_buf.c0Rx))
        begin
            afu_buf.c0Rx.hdr = { fiu_buf.c0Rx.hdr[CCI_C0RX_MEMHDR_WIDTH-1 : $bits(t_C0_REQ_IDX)], c0_heap_readRsp.mdata };
        end
    end


    // ====================================================================
    //
    //  Channel 1 (write)
    //
    // ====================================================================

    // If request is a write update the Mdata with the index of the hash
    // details.
    always_comb
    begin
        fiu_buf.c1Tx = cci_mpf_c1TxMaskValids(afu_pipe[1].c1Tx, process_requests);

        if (cci_mpf_c1TxIsWriteReq(afu_pipe[1].c1Tx))
        begin
            fiu_buf.c1Tx.hdr.base.mdata[$bits(c1_heap_allocIdx)-1 : 0] = c1_heap_allocIdx;
        end
    end

    // Save state that will be used when the response is returned.
    assign c1_heap_enqData.mdata = t_C1_REQ_IDX'(afu_pipe[1].c1Tx.hdr.base.mdata);

    // Request heap read as fiu responses arrive. The heap's value will be
    // available the cycle fiu_buf is read. Responses may arrive on either
    // channel!
    assign c1_heap_readReq = t_C1_REQ_IDX'(fiu.c1Rx.hdr);

    // Free heap entries as write responses arrive.
    assign c1_heap_freeIdx = t_C1_REQ_IDX'(fiu.c1Rx.hdr);
    assign c1_heap_free = cci_c1Rx_isWriteRsp(fiu.c1Rx);

    // Either forward the header from the FIU for non-read responses or
    // reconstruct the read response header.
    always_comb
    begin
        afu_buf.c1Rx = fiu_buf.c1Rx;

        if (cci_c1Rx_isWriteRsp(fiu_buf.c1Rx))
        begin
            afu_buf.c1Rx.hdr = { fiu_buf.c1Rx.hdr[CCI_C1RX_MEMHDR_WIDTH-1 : $bits(t_C1_REQ_IDX)], c1_heap_readRsp.mdata };
        end
    end

`ifdef DEBUG_MESSAGES
    t_C0_REQ_IDX c0_prev_heap_allocIdx;
    t_C1_REQ_IDX c1_prev_heap_allocIdx;
    logic [15:0] cycle;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            c0_prev_heap_allocIdx <= 0;
            c1_prev_heap_allocIdx <= 0;
            cycle <= 0;
        end
        else
        begin
            cycle <= cycle + 1;

            if (c0_blocked && ! c0_filter_may_insert && (c0_heap_allocIdx != c0_prev_heap_allocIdx))
            begin
                c0_prev_heap_allocIdx <= c0_heap_allocIdx;
                $display("C0 blocked %d", c0_heap_allocIdx);
            end
            if (c1_blocked && ! c1_filter_may_insert && (c1_heap_allocIdx != c1_prev_heap_allocIdx))
            begin
                c1_prev_heap_allocIdx <= c1_heap_allocIdx;
                $display("C1 blocked %d", c1_heap_allocIdx);
            end

            if (cci_mpf_c0TxIsReadReq(fiu_buf.c0Tx))
            begin
                $display("XX A 0 %d %x %d",
                         c0_heap_allocIdx,
                         getReqAddrMPF(fiu_buf.c0Tx.hdr),
                         cycle);
            end
            if (cci_mpf_c1TxIsWriteReq(fiu_buf.c1Tx))
            begin
                $display("XX A 1 %d %x %d",
                         c1_heap_allocIdx,
                         getReqAddrMPF(fiu_buf.c1Tx.hdr),
                         cycle);
            end

            if (c0_heap_free)
            begin
                $display("XX R 0 %0d %d",
                         c0_heap_freeIdx, cycle);
            end
            if (c1_heap_free)
            begin
                $display("XX W 1 %0d %d",
                         c1_heap_freeIdx, cycle);
            end
        end
    end
`endif


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign fiu_buf.c2Tx = afu_buf.c2Tx;

endmodule // cci_mpf_shim_wro
