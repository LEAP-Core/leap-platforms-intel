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


//
// Manage response ordering and Mdata initialization.  This module is
// typically instantiated closest to the AFU in the MPF hierarchy.
//
// Many MPF shims depend on some Mdata bits being either zero or
// ignored by other layers.  This module is responsible for configuring
// Mdata in requests for use by other shims while preserving the AFU's
// metadata.
//
// The module has multiple options:
//
//   -- SORT_READ_RESPONSES:  Optionally sort read responses so they are
//      returned in the same order they were requested.
//
//   -- PRESERVE_WRITE_MDATA:  Optionally preserve Mdata for write
//      request/response pairs.  When false the Mdata returned with write
//      responses is always 0.  Read Mdata is always preserved.
//
//

module cci_mpf_shim_rsp_order
  #(
    // Sort read responses?  CCI returns responses out of order.  This
    // module can instantiate a reorder buffer to return responses
    // in the order they were requested.
    //
    // Note: Mdata for read responses is ALWAYS preserved.  When sorting
    // is disabled Mdata is the only method for the client to match
    // responses.  When sorting is enabled the size of Mdata relative to
    // the size of the reorder buffer is irrelevant and thus not worth
    // the extra logic to optionally drop Mdata.  Quartus will likely
    // delete dead code on its own.
    parameter SORT_READ_RESPONSES = 1,

    // Preserve Mdata field in write requests?  Clients that merely count
    // active writes might not use Mdata for writes, so the block RAM
    // required for preservation can be saved.
    parameter PRESERVE_WRITE_MDATA = 1,

    // Maximum number of in-flight reads and writes. (Per category - the
    // total number of in-flight operations is 2 * N_SCOREBOARD_ENTRIES.)
    parameter N_SCOREBOARD_ENTRIES = 256,

    // Synchronize request channels if non-zero. Channel synchronization is
    // required to preserve load/store ordering.
    parameter SYNC_REQ_CHANNELS = 1
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu
    );

    logic reset_n;
    assign reset_n = fiu.reset_n;
    assign afu.reset_n = fiu.reset_n;

    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_scoreboard_idx;

    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_heap_idx;

    // Full signals that will come from the scoreboard and heap used to
    // sort responses.
    logic rd_scoreboard_notFull;
    logic wr_heap_notFull;


    // ====================================================================
    //
    //  The scoreboard is allocated with enough reserve space so that
    //  it honors the almost full semantics. No other buffering is
    //  required.
    //
    //  When SYNC_REQ_CHANNELS is true, Assert almost full if either
    //  request channel is filling so that the two channels stay
    //  synchronized. This maintains load/store order.
    //
    // ====================================================================

    logic c0_TxAlmFull;
    assign c0_TxAlmFull = fiu.c0TxAlmFull || ! rd_scoreboard_notFull;

    logic c1_TxAlmFull;
    assign c1_TxAlmFull = fiu.c1TxAlmFull || ! wr_heap_notFull;

    generate
        if (SYNC_REQ_CHANNELS == 0)
        begin
            assign afu.c0TxAlmFull = c0_TxAlmFull;
            assign afu.c1TxAlmFull = c1_TxAlmFull;
        end
        else
        begin
            assign afu.c0TxAlmFull = c0_TxAlmFull || c1_TxAlmFull;
            assign afu.c1TxAlmFull = c0_TxAlmFull || c1_TxAlmFull;
        end
    endgenerate


    // ====================================================================
    //
    //  Allocate a heap for preserving Mdata fields in writes.  This
    //  could logically be a separate shim but doing so would cost an
    //  extra cycle in load responses in order to read the Mdata out of
    //  block RAM.
    //
    // ====================================================================

    t_heap_idx wr_heap_allocIdx;
    t_heap_idx wr_heap_readIdx[0:1];
    t_cci_mdata wr_heap_readMdata[0:1];

    logic wr_heap_free[0:1];

    generate
        //
        // Does the configuration require preserving Mdata for writes?
        //
        if (PRESERVE_WRITE_MDATA)
        begin : gen_wr_heap
            cci_mpf_prim_heap_multi
              #(
                .N_ENTRIES(N_SCOREBOARD_ENTRIES),
                .N_DATA_BITS(CCI_MDATA_WIDTH),
                .N_READ_PORTS(2),
                .MIN_FREE_SLOTS(CCI_ALMOST_FULL_THRESHOLD)
                )
              wr_heap
               (
                .clk,
                .reset_n,

                .enq(afu.c1Tx.wrValid),
                .enqData(afu.c1Tx.hdr.base.mdata),
                .notFull(wr_heap_notFull),
                .allocIdx(wr_heap_allocIdx),

                .readReq(wr_heap_readIdx),
                .readRsp(wr_heap_readMdata),
                .free(wr_heap_free),
                .freeIdx(wr_heap_readIdx)
                );
        end
        else
        begin : no_wr_heap
            //
            // Can overwrite Mdata without preserving it.  Some downstream
            // MPF modules depend on finding zero bits in Mdata, so set up
            // the dangling heap wires to clear Mdata.
            //
            assign wr_heap_notFull = 1'b1;
            assign wr_heap_allocIdx = t_heap_idx'(0);
            assign wr_heap_readMdata[0] = t_cci_mdata'(0);
            assign wr_heap_readMdata[1] = t_cci_mdata'(0);
        end
    endgenerate


    // ====================================================================
    //
    // Buffer for responses to allow a cycle for heap lookup.  If we aren't
    // sorting reads or preserving Mdata for writes then the buffer isn't
    // needed.  In that case just make it an alias for the incoming data.
    //
    // ====================================================================

    cci_mpf_if fiu_buf (.clk);
    assign fiu_buf.reset_n = fiu.reset_n;

    generate
        //
        // Does the configuration require preserving Mdata for writes or
        // reads?
        //
        if ((SORT_READ_RESPONSES == 0) || PRESERVE_WRITE_MDATA)
        begin : gen_fiu_buf
            always_ff @(posedge clk)
            begin
                fiu_buf.c0Rx <= fiu.c0Rx;
                fiu_buf.c1Rx <= fiu.c1Rx;
            end
        end
        else
        begin : no_fiu_buf
            always_comb
            begin
                fiu_buf.c0Rx = fiu.c0Rx;
                fiu_buf.c1Rx = fiu.c1Rx;
            end
        end
    endgenerate


    // ====================================================================
    //
    //  Channel 0 (read)
    //
    // ====================================================================

    t_scoreboard_idx rd_scoreboard_enqIdx;

    logic rd_scoreboard_notEmpty;
    t_cci_mdata rd_scoreboard_mdata;
    t_cci_mdata rd_heap_readMdata;

    t_cci_cldata rd_scoreboard_outData;

    generate
        if (SORT_READ_RESPONSES)
        begin : gen_rd_scoreboard
            //
            // Read responses are sorted.  Allocate a scoreboard as
            // a reorder buffer.
            //
            cci_mpf_prim_scoreboard
              #(
                .N_ENTRIES(N_SCOREBOARD_ENTRIES),
                .N_DATA_BITS(CCI_CLDATA_WIDTH),
                .N_META_BITS(CCI_MDATA_WIDTH),
                .MIN_FREE_SLOTS(CCI_ALMOST_FULL_THRESHOLD)
                )
              rd_scoreboard
               (
                .clk,
                .reset_n,

                .enq_en(afu.c0Tx.rdValid),
                .enqMeta(afu.c0Tx.hdr.base.mdata),
                .notFull(rd_scoreboard_notFull),
                .enqIdx(rd_scoreboard_enqIdx),

                .enqData_en(fiu.c0Rx.rdValid),
                .enqDataIdx(t_scoreboard_idx'(fiu.c0Rx.hdr.mdata)),
                .enqData(fiu.c0Rx.data),

                .deq_en(afu.c0Rx.rdValid),
                .notEmpty(rd_scoreboard_notEmpty),
                .first(rd_scoreboard_outData),
                .firstMeta(rd_scoreboard_mdata)
                );
        end
        else
        begin
            //
            // Read responses are not sorted.  Allocate a heap to
            // preserve Mdata.
            //
            cci_mpf_prim_heap
              #(
                .N_ENTRIES(N_SCOREBOARD_ENTRIES),
                .N_DATA_BITS(CCI_MDATA_WIDTH),
                .MIN_FREE_SLOTS(CCI_ALMOST_FULL_THRESHOLD)
                )
              rd_heap
               (
                .clk,
                .reset_n,

                .enq(afu.c0Tx.rdValid),
                .enqData(afu.c0Tx.hdr.base.mdata),
                .notFull(rd_scoreboard_notFull),
                .allocIdx(rd_scoreboard_enqIdx),

                .readReq(t_scoreboard_idx'(fiu.c0Rx.hdr.mdata)),
                .readRsp(rd_heap_readMdata),
                .free(fiu.c0Rx.rdValid),
                .freeIdx(t_scoreboard_idx'(fiu.c0Rx.hdr.mdata))
                );
        end
    endgenerate

    // Forward requests toward the FIU.  Replace the Mdata entry with the
    // scoreboard index.  The original Mdata is saved in the scoreboard
    // and restored when the response is returned.
    always_comb
    begin
        fiu.c0Tx = afu.c0Tx;
        fiu.c0Tx.hdr.base.mdata = t_cci_mdata'(rd_scoreboard_enqIdx);
    end

    logic c0_non_rd_valid;

    //
    // Responses
    //
    always_comb
    begin
        afu.c0Rx = fiu_buf.c0Rx;

        // Is there a non-read response active?
        c0_non_rd_valid = fiu_buf.c0Rx.wrValid ||
                          fiu_buf.c0Rx.cfgValid ||
                          fiu_buf.c0Rx.umsgValid ||
                          fiu_buf.c0Rx.intrValid;

        // Forward responses toward AFU as they become available in sorted order.
        // Non-read responses on the channel have priority since they are
        // unbuffered.
        if (SORT_READ_RESPONSES)
        begin
            afu.c0Rx.data = rd_scoreboard_outData;
            afu.c0Rx.rdValid = rd_scoreboard_notEmpty && ! c0_non_rd_valid;
        end

        // Either forward the header from the FIU for non-read responses or
        // reconstruct the read response header.  The CCI-E header has the same
        // low bits as CCI-S so we always construct CCI-E and truncate when
        // in CCI-S mode.
        if (afu.c0Rx.rdValid && SORT_READ_RESPONSES)
        begin
            afu.c0Rx.hdr = cci_genRspHdr(eRSP_RDLINE, rd_scoreboard_mdata);
        end
        else
        begin
            afu.c0Rx.hdr = fiu_buf.c0Rx.hdr;

            // Return preserved Mdata
            if (afu.c0Rx.rdValid)
            begin
                // This path reached only when SORT_READ_RESPONSES == 0.
                afu.c0Rx.hdr.mdata = rd_heap_readMdata;
            end
            else if (afu.c0Rx.wrValid)
            begin
                afu.c0Rx.hdr.mdata = wr_heap_readMdata[0];
            end
        end
    end

    // Lookup write heap to restore Mdata
    assign wr_heap_readIdx[0] = t_heap_idx'(fiu.c0Rx.hdr.mdata);
    assign wr_heap_free[0] = fiu.c0Rx.wrValid;


    // ====================================================================
    //
    //  Channel 1 (write) flows straight through.
    //
    // ====================================================================

    // Requests: replace the Mdata field with the heap index that holds
    // the preserved value.  This can be done unconditionally since only
    // writes use Mdata on the channel and only wrValid is the enq signal
    // that increments the heap index.
    always_comb
    begin
        fiu.c1Tx = afu.c1Tx;
        fiu.c1Tx.hdr.base.mdata = t_cci_mdata'(wr_heap_allocIdx);
    end

    // Responses
    always_comb
    begin
        afu.c1Rx = fiu_buf.c1Rx;

        // If a write response return the preserved Mdata
        if (afu.c1Rx.wrValid)
        begin
            afu.c1Rx.hdr.mdata = wr_heap_readMdata[1];
        end
    end

    // Lookup write heap to restore Mdata
    assign wr_heap_readIdx[1] = t_heap_idx'(fiu.c1Rx.hdr.mdata);
    assign wr_heap_free[1] = fiu.c1Rx.wrValid;

endmodule // cci_mpf_shim_rsp_order

