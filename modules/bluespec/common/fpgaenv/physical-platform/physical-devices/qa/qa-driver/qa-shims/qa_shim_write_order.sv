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

`include "qa_driver.vh"
`include "qa_drv_prim_hash.vh"


//
// Guarantee that writes to the same address complete in order and that reads
// to addresses matching writes complete in order relative to the write.
//


module qa_shim_write_order
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13,

    // Size of the incoming buffer.  It must be at least as large as the
    // threshold below.
    parameter N_AFU_BUF_ENTRIES = 6,
    // Threshold of free entries at which almost full is asserted.
    parameter AFU_BUF_THRESHOLD = 4
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    qlp_interface.to_qlp qlp,

    // Connections toward user code.
    qlp_interface.to_afu afu
    );

    logic resetb;
    assign resetb = qlp.resetb;

    // ====================================================================
    //
    //  Characteristics of the counting Bloom filters.
    //
    // ====================================================================

    // Number of hashes in each filter.
    localparam N_HASHES = 3;

    // t_HASH defines the number of entries in each Bloom filter hash
    // bucket.
    typedef logic [3:0] t_HASH;
    typedef t_HASH [0 : N_HASHES-1] t_HASH_GROUP;

    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqTx;

    qa_shim_buffer_lockstep_afu
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH),
        .N_ENTRIES(N_AFU_BUF_ENTRIES),
        .THRESHOLD(AFU_BUF_THRESHOLD)
        )
      bufafu
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqTx
         );

    assign afu_buf.resetb = qlp.resetb;

    //
    // Almost full signals in the buffered input are ignored --
    // replaced by deq signals and the buffer state.  Set them
    // to 1 to be sure they are ignored.
    //
    assign afu_buf.C0TxAlmFull = 1'b1;
    assign afu_buf.C1TxAlmFull = 1'b1;


    // ====================================================================
    //
    //  Instantiate a buffer on the QLP response port to give time to
    //  read local state in block RAMs before forwarding the response
    //  toward the AFU.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      qlp_buf (.clk);

    qa_shim_buffer_qlp
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      bufqlp
        (
         .clk,
         .qlp_raw(qlp),
         .qlp_buf(qlp_buf)
         );


    // ====================================================================
    //
    //  Incoming requests.
    //
    // ====================================================================

    // Is either AFU making a request?
    logic c0_request_rdy;
    assign c0_request_rdy = afu_buf.C0TxRdValid;

    logic c1_request_rdy;
    assign c1_request_rdy = afu_buf.C1TxWrValid || afu_buf.C1TxIrValid;

    // Full/empty signals that will come from the heap and filters
    logic c0_heap_notFull;
    logic c0_filter_notFull;
    logic c0_filter_hasZero;
    logic c1_filter_notFull;
    logic c1_filter_hasZero;

    // Is a request blocked by inability to forward it to the QLP or a
    // conflict?  c0_filter_notFull asserts that the read filter counters
    // can be incremented.  c0_filter_hasZero asserts that no store is
    // in flight to the same address.
    logic c0_blocked;
    assign c0_blocked = c0_request_rdy &&
                        (qlp_buf.C0TxAlmFull || ! c0_heap_notFull ||
                         ! c0_filter_notFull || ! c0_filter_hasZero);

    logic c1_blocked;
    assign c1_blocked = c1_request_rdy &&
                        (qlp_buf.C1TxAlmFull ||
                         ! c1_filter_notFull || ! c1_filter_hasZero);

    // Process requests if one exists on either channel AND neither channel
    // is blocked.  The requirement that neither channel be blocked keeps
    // the two channels synchronized with respect to each other so that
    // read and write requests stay ordered relative to each other.
    logic process_requests;
    assign process_requests = (c0_request_rdy || c1_request_rdy) &&
                              ! (c0_blocked || c1_blocked);


    // ====================================================================
    //
    //  Heaps to hold old Mdata and hash info.
    //
    // ====================================================================

    typedef logic [7:0] t_HEAP_IDX;

    typedef struct packed
    {
        // Save the part of the request's Mdata that is overwritten by the
        // heap index.
        t_HEAP_IDX mdata;
        t_HASH_GROUP hash;
    }
    t_HEAP_ENTRY;

    t_HEAP_ENTRY c0_heap_enqData;
    t_HEAP_IDX c0_heap_allocIdx;

    t_HEAP_IDX c0_heap_readReq;
    t_HEAP_ENTRY c0_heap_readRsp;

    logic c0_heap_free;
    t_HEAP_IDX c0_heap_freeIdx;

    qa_drv_prim_heap
      #(
        .N_ENTRIES(1 << $bits(t_HEAP_IDX)),
        .N_DATA_BITS($bits(t_HEAP_ENTRY))
        )
      c0_heap(.clk,
              .resetb,
              .enq(qlp_buf.C0TxRdValid),
              .enqData(c0_heap_enqData),
              .notFull(c0_heap_notFull),
              .allocIdx(c0_heap_allocIdx),
              .readReq(c0_heap_readReq),
              .readRsp(c0_heap_readRsp),
              .free(c0_heap_free),
              .freeIdx(c0_heap_freeIdx)
              );


    // ====================================================================
    //
    //  Counting Bloom filter to track busy addresses.  By using counters
    //  in the filter buckets the filter never has to be cleared.  Entries
    //  can be removed as requests retire.
    //
    // ====================================================================

    // Tests are indexed by the filter instance and the two request channels.
    // Both request channels are checked in parallel for each filter.
    t_HASH [0 : N_HASHES-1][0 : 1] filter_test_req;
    t_HASH [0 : N_HASHES-1][0 : 1] filter_test_req_in;

    // A FIFO of identical depth to bufafu for olding the hashed addresses.
    // This is necessary for timing.
    qa_drv_prim_fifo_lutram
      #(
        .N_DATA_BITS($bits(filter_test_req)),
        .N_ENTRIES(N_AFU_BUF_ENTRIES),
        .THRESHOLD(AFU_BUF_THRESHOLD)
        )
      bufhash
        (.clk,
         .resetb(qlp.resetb),

         .enq_data(filter_test_req_in),
         .enq_en(afu.C0TxRdValid || afu.C1TxWrValid || afu.C1TxIrValid),
         // Ignore the control signals.  afu_buf is the same size.
         .notFull(),
         .almostFull(),

         .first(filter_test_req),
         .deq_en(deqTx),
         .notEmpty()
         );

    // There are two sets of filters: one for reads and one for writes.
    // They exist because multiple reads can be outstanding to a single
    // address but only one store may be live.
    logic  [0 : N_HASHES-1][0 : 1] rd_filter_test_notFull;
    logic  [0 : N_HASHES-1][0 : 1] rd_filter_test_isZero;
    logic  [0 : N_HASHES-1][0 : 1] wr_filter_test_notFull;
    logic  [0 : N_HASHES-1][0 : 1] wr_filter_test_isZero;

    logic c1_filter_hasZero_rd;
    logic c1_filter_hasZero_wr;
    assign c1_filter_hasZero = c1_filter_hasZero_rd && c1_filter_hasZero_wr;

    //
    // Compute whether new requests can be inserted into the filters.
    // c0 is read requests, c1 is write requests.
    //
    // Each Bloom filter has N_HASHES hashes.  An entry is in the set when
    // the counter associated with each hash is non-zero.  An entry is not
    // in the set when at least one counter is zero.
    //
    always_comb
    begin
        c0_filter_notFull = 1'b1;
        c1_filter_notFull = 1'b1;

        c0_filter_hasZero = 1'b0;
        c1_filter_hasZero_rd = 1'b0;
        c1_filter_hasZero_wr = 1'b0;

        for (int i = 0; i < N_HASHES; i = i + 1)
        begin
            // The full test is on the filter that will be updated by the
            // new request.  For c0 that is the read filter and for c1 the
            // write filter.
            c0_filter_notFull = c0_filter_notFull && rd_filter_test_notFull[i][0];
            c1_filter_notFull = c1_filter_notFull && wr_filter_test_notFull[i][1];

            // hasZero is a test that no other reference to the same address
            // is in flight.  Reads require hasZero only of writes since
            // two reads may be in flight to the same address.
            c0_filter_hasZero = c0_filter_hasZero || wr_filter_test_isZero[i][0];

            // Writes require that no read and no write be outstanding to
            // the address.
            c1_filter_hasZero_rd = c1_filter_hasZero_rd || rd_filter_test_isZero[i][1];
            c1_filter_hasZero_wr = c1_filter_hasZero_wr || wr_filter_test_isZero[i][1];
        end
    end

    t_HASH [0 : N_HASHES-1][0 : 1] wr_filter_remove;
    logic  [0 : 1] wr_filter_remove_en;

    //
    // Generate the read and write Bloom filters.  Each Bloom filter is
    // the composition of N_HASHES hash functions.
    //
    genvar f;
    generate
        for (f = 0; f < N_HASHES; f = f + 1)
        begin : bloom
            qa_drv_prim_counting_filter
              #(
                .N_BUCKETS(16),
                .BITS_PER_BUCKET($size(t_HASH)),
                .N_TEST_CLIENTS(2),
                .N_INSERT_CLIENTS(1),
                .N_REMOVE_CLIENTS(1)
                )
              rd_filter(.clk,
                        .resetb,
                        .test_req(filter_test_req[f]),
                        .test_notFull(rd_filter_test_notFull[f]),
                        .test_isZero(rd_filter_test_isZero[f]),
                        .insert(filter_test_req[f][0]),
                        .insert_en(qlp_buf.C0TxRdValid),
                        .remove(c0_heap_readRsp.hash[f]),
                        .remove_en(qlp_buf.C0RxRdValid));

            //
            // The write filter has two remove clients since write responses
            // can come back on either port.
            //
            qa_drv_prim_counting_filter
              #(
                .N_BUCKETS(16),
                .BITS_PER_BUCKET($size(t_HASH)),
                .N_TEST_CLIENTS(2),
                .N_INSERT_CLIENTS(1),
                .N_REMOVE_CLIENTS(2)
                )
              wr_filter(.clk,
                        .resetb,
                        .test_req(filter_test_req[f]),
                        .test_notFull(wr_filter_test_notFull[f]),
                        .test_isZero(wr_filter_test_isZero[f]),
                        .insert(filter_test_req[f][1]),
                        .insert_en(qlp_buf.C1TxWrValid),
                        .remove(wr_filter_remove[f]),
                        .remove_en(wr_filter_remove_en));
        end
    endgenerate

    //
    // Pick filter buckets based on hashes of incoming request addresses.
    //
    
    // Start by expanding the addresses to 64 bits.  The hash is computed
    // on the way in to the afu_buf and stored in a FIFO the same size
    // as the buffer in order to reduce timing pressure at the point the
    // filter is checked and updated.
    logic [63:0] c0_req_addr;
    assign c0_req_addr = 64'(getReqAddrCCIE(t_TX_HEADER_CCI_E'(afu.C0TxHdr)));

    logic [63:0] c1_req_addr;
    assign c1_req_addr = 64'(getReqAddrCCIE(t_TX_HEADER_CCI_E'(afu.C1TxHdr)));

    // Hash them
    logic [31:0] c0_addr_hash;
    assign c0_addr_hash = hash32(c0_req_addr[63:32] ^ c0_req_addr[31:0]);

    logic [31:0] c1_addr_hash;
    assign c1_addr_hash = hash32(c1_req_addr[63:32] ^ c1_req_addr[31:0]);

    // Use different bit ranges from the hash as Bloom filter indices
    assign filter_test_req_in[0][0] = c0_addr_hash[3:0];
    assign filter_test_req_in[1][0] = c0_addr_hash[7:4];
    assign filter_test_req_in[2][0] = c0_addr_hash[11:8];

    assign filter_test_req_in[0][1] = c1_addr_hash[3:0];
    assign filter_test_req_in[1][1] = c1_addr_hash[7:4];
    assign filter_test_req_in[2][1] = c1_addr_hash[11:8];


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    // Forward requests toward the QLP.  Replace part of the Mdata entry
    // with the scoreboard index.  The original Mdata is saved in the
    // heap and restored when the response is returned.
    assign qlp_buf.C0TxHdr = { afu_buf.C0TxHdr[CCI_TX_HDR_WIDTH-1 : $bits(t_HEAP_IDX)],
                               c0_heap_allocIdx };
    assign deqTx = process_requests;
    assign qlp_buf.C0TxRdValid = process_requests && c0_request_rdy;

    // Save state that will be used when the response is returned.
    assign c0_heap_enqData.mdata = t_HEAP_IDX'(afu_buf.C0TxHdr);
    assign c0_heap_enqData.hash = { filter_test_req[0][0], filter_test_req[1][0], filter_test_req[2][0] };

    // Request heap read as qlp responses arrive.  The heap's value will be
    // available the cycle qlp_buf is read.
    assign c0_heap_readReq = t_HEAP_IDX'(qlp.C0RxHdr);

    // Free heap entries as read responses arrive.
    assign c0_heap_freeIdx = t_HEAP_IDX'(qlp.C0RxHdr);
    assign c0_heap_free = qlp.C0RxRdValid;

    assign afu_buf.C0RxData    = qlp_buf.C0RxData;
    assign afu_buf.C0RxWrValid = qlp_buf.C0RxWrValid;
    assign afu_buf.C0RxRdValid = qlp_buf.C0RxRdValid;
    assign afu_buf.C0RxCgValid = qlp_buf.C0RxCgValid;
    assign afu_buf.C0RxUgValid = qlp_buf.C0RxUgValid;
    assign afu_buf.C0RxIrValid = qlp_buf.C0RxIrValid;

    // Either forward the header from the QLP for non-read responses or
    // reconstruct the read response header.  The CCI-E header has the same
    // low bits as CCI-S so we always construct CCI-E and truncate when
    // in CCI-S mode.
    assign afu_buf.C0RxHdr =
        qlp_buf.C0RxRdValid ?
            { qlp_buf.C0RxHdr[CCI_RX_HDR_WIDTH-1 : $bits(t_HEAP_IDX)], c0_heap_readRsp.mdata } :
            qlp_buf.C0RxHdr;


    // ====================================================================
    //
    //  Channel 1 (write)
    //
    // ====================================================================

    t_HASH [0 : N_HASHES-1] c1_tx_hash;

    assign qlp_buf.C1TxHdr =
        afu_buf.C1TxWrValid ?
            { afu_buf.C1TxHdr[CCI_TX_HDR_WIDTH-1 : $bits(c1_tx_hash)], c1_tx_hash } :
            afu_buf.C1TxHdr;

    assign qlp_buf.C1TxData = afu_buf.C1TxData;
    assign qlp_buf.C1TxWrValid = afu_buf.C1TxWrValid && process_requests;
    assign qlp_buf.C1TxIrValid = afu_buf.C1TxIrValid && process_requests;

    // Responses
    assign afu_buf.C1RxHdr = qlp_buf.C1RxHdr;
    assign afu_buf.C1RxWrValid = qlp_buf.C1RxWrValid;
    assign afu_buf.C1RxIrValid = qlp_buf.C1RxIrValid;

    //
    // Write responses can come back on either channel.  Handle both here.
    //
    t_HASH [0 : N_HASHES-1] c0_rx_hash;
    assign c0_rx_hash = $bits(c0_rx_hash)'(qlp_buf.C0RxHdr);
    t_HASH [0 : N_HASHES-1] c1_rx_hash;
    assign c1_rx_hash = $bits(c1_rx_hash)'(qlp_buf.C1RxHdr);

    assign wr_filter_remove_en[0] = qlp_buf.C0RxWrValid;
    assign wr_filter_remove_en[1] = qlp_buf.C1RxWrValid;

    generate
        for (f = 0; f < N_HASHES; f = f + 1)
        begin : c1_remove
            assign c1_tx_hash[f] = filter_test_req[f][1];

            assign wr_filter_remove[f][0] = c0_rx_hash[f];
            assign wr_filter_remove[f][1] = c1_rx_hash[f];
        end
    endgenerate

endmodule // qa_shim_write_order

