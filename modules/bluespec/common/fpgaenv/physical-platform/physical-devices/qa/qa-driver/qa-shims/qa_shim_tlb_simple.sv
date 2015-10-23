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
`include "qa_shim_tlb_simple_params.h"

//
// Map virtual to physical addresses.  The AFU and QLP interfaces are thus
// difference widths.
//

module qa_shim_tlb_simple
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_QLP_RX_HDR_WIDTH = 18,
    parameter CCI_QLP_TX_HDR_WIDTH = 61,
    parameter CCI_AFU_RX_HDR_WIDTH = 24,
    parameter CCI_AFU_TX_HDR_WIDTH = 99,
    parameter CCI_TAG_WIDTH = 13
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
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_AFU_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_AFU_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqC0Tx;
    logic deqC1Tx;

    qa_shim_buffer_afu
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_AFU_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_AFU_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      buffer
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqC0Tx,
         .deqC1Tx
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
        .CCI_RX_HDR_WIDTH(CCI_QLP_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_QLP_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      qlp_buf (.clk);

    qa_shim_buffer_qlp
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_QLP_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_QLP_TX_HDR_WIDTH),
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
    //  Heap to hold old Mdata.  Only read requests and responses have
    //  modified Mdata fields.
    //
    // ====================================================================

    // Number of reads can be relatively large since a block RAM will be
    // allocated for the Mdata storage.
    localparam MAX_ACTIVE_READS = 128;

    // Heap entry index
    typedef logic [$clog2(MAX_ACTIVE_READS)-1 : 0] t_C0_REQ_IDX;

    // Module-specific data stored in Mdata requests
    typedef struct packed
    {
        // Read from the page table requested by this module?
        logic isPageTableLine;

        // Saved Mdata from a client read
        t_C0_REQ_IDX heapIdx;
    }
    t_C0_MDATA;

    // Heap entry holding a requests original Mdata
    typedef logic [$bits(t_C0_MDATA)-1 : 0] t_C0_HEAP_ENTRY;

    t_C0_HEAP_ENTRY c0_heap_enqData;
    t_C0_REQ_IDX c0_heap_allocIdx;

    logic c0_heap_notFull;

    t_C0_REQ_IDX c0_heap_readReq;
    t_C0_HEAP_ENTRY c0_heap_readRsp;

    logic c0_heap_free;
    t_C0_REQ_IDX c0_heap_freeIdx;

    qa_drv_prim_heap
      #(
        .N_ENTRIES(MAX_ACTIVE_READS),
        .N_DATA_BITS($bits(t_C0_HEAP_ENTRY))
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
    //  Requests
    //
    // ====================================================================

    assign deqC0Tx = afu_buf.C0TxRdValid && ! qlp.C0TxAlmFull && c0_heap_notFull;
    assign qlp_buf.C0TxRdValid = deqC0Tx;

    // Add module-specific data to Mdata in order to route the response
    t_C0_MDATA req_mdata;
    assign req_mdata.isPageTableLine = 0;
    assign req_mdata.heapIdx = c0_heap_allocIdx;
    assign qlp_buf.C0TxHdr =
        { afu_buf.C0TxHdr[CCI_QLP_TX_HDR_WIDTH-1 : $bits(t_C0_HEAP_ENTRY)],
          req_mdata };

    // Save state that will be used when the response is returned.
    assign c0_heap_enqData = t_C0_HEAP_ENTRY'(afu_buf.C0TxHdr);


    // Channel 1 (write) requests go straight through.
    assign deqC1Tx = (afu_buf.C1TxWrValid || afu_buf.C1TxIrValid) &&
                     ! qlp.C1TxAlmFull;

    assign qlp_buf.C1TxHdr = CCI_QLP_TX_HDR_WIDTH'(afu_buf.C1TxHdr);
    assign qlp_buf.C1TxData = afu_buf.C1TxData;
    assign qlp_buf.C1TxWrValid = afu_buf.C1TxWrValid && deqC1Tx;
    assign qlp_buf.C1TxIrValid = afu_buf.C1TxIrValid && deqC1Tx;


    // ====================================================================
    //
    //  Responses
    //
    // ====================================================================

    // Request heap read as qlp responses arrive.  The heap's value will be
    // available the cycle qlp_buf is read.
    assign c0_heap_readReq = t_C0_REQ_IDX'(qlp.C0RxHdr);

    // Free heap entries as read responses arrive.
    assign c0_heap_freeIdx = t_C0_REQ_IDX'(qlp.C0RxHdr);
    assign c0_heap_free = qlp.C0RxRdValid;

    assign afu_buf.C0RxData    = qlp_buf.C0RxData;
    assign afu_buf.C0RxWrValid = qlp_buf.C0RxWrValid;
    assign afu_buf.C0RxRdValid = qlp_buf.C0RxRdValid;
    assign afu_buf.C0RxCgValid = qlp_buf.C0RxCgValid;
    assign afu_buf.C0RxUgValid = qlp_buf.C0RxUgValid;
    assign afu_buf.C0RxIrValid = qlp_buf.C0RxIrValid;

    // Either forward the header from the QLP for non-read responses or
    // reconstruct the read response header.
    always_comb
    begin
        if (qlp_buf.C0RxRdValid)
        begin
            afu_buf.C0RxHdr =
                { qlp_buf.C0RxHdr[CCI_QLP_RX_HDR_WIDTH-1 : $bits(t_C0_HEAP_ENTRY)],
                  c0_heap_readRsp };
        end
        else
        begin
            afu_buf.C0RxHdr = qlp_buf.C0RxHdr;
        end
    end


    // Channel 1 (write) responses can flow directly from the QLP port since
    // there is no processing needed here.
    assign afu_buf.C1RxHdr = CCI_AFU_RX_HDR_WIDTH'(qlp.C1RxHdr);
    assign afu_buf.C1RxWrValid = qlp.C1RxWrValid;
    assign afu_buf.C1RxIrValid = qlp.C1RxIrValid;

endmodule // qa_shim_tlb_simple
