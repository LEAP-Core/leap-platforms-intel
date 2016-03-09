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
`include "cci_mpf_csrs.vh"

`include "cci_mpf_shim_vtp.vh"


//
// Primary virtual to physical address translation pipeline.  The TLB
// is provided as an interface.
//
//                             * * * * * * * *
//
//   This module freely reorders memory references, including load/store
//   and store/store order without comparing addresses.  This is a standard
//   property of CCI.  If order is important in your memory subsystem then
//   requests coming from an AFU should be filtered by address before
//   reaching this module to guarantee order within a line.
//   cci_mpf_shim_write_order.sv provides this function and is included in the
//   reference memory subsystem.
//
//                             * * * * * * * *
//

module cci_mpf_shim_vtp_pipe
  #(
    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    // CSRs
    cci_mpf_csrs.vtp csrs,

    // TLB lookup
    cci_mpf_shim_vtp_tlb_if.client tlb_if
    );

    logic reset;
    assign reset = fiu.reset;


    // ====================================================================
    //
    //  Instantiate a buffer on the AFU request port, making it latency
    //  insensitive.
    //
    // ====================================================================

    cci_mpf_if afu_buf (.clk);

    // Latency-insensitive ports need explicit dequeue (enable).
    logic deqC0Tx;
    logic deqC1Tx;

    cci_mpf_shim_buffer_afu
      #(
        .ENABLE_C0_BYPASS(1)
        )
      buffer
        (
         .clk,
         .afu_raw(afu),
         .afu_buf(afu_buf),
         .deqC0Tx,
         .deqC1Tx
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
    //  TLB lookup pipeline
    //
    // ====================================================================

    //
    // Request data flowing through each channel
    //

    // Pipeline stage storage
    localparam AFU_PIPE_LAST_STAGE = 5;
    t_if_cci_mpf_c0_Tx c0_afu_pipe[0 : AFU_PIPE_LAST_STAGE];
    t_if_cci_mpf_c1_Tx c1_afu_pipe[0 : AFU_PIPE_LAST_STAGE];

    // Stage at which request is sent to TLB
    localparam AFU_PIPE_LOOKUP_STAGE = 1;

    // Stage to which retry wraps back
    localparam AFU_PIPE_RETRY_STAGE = 1;

    //
    // Work backwards in the pipeline.  First decide whether the oldest
    // request can fire.  If it can (or there is no request) then younger
    // requests will ripple through the pipeline.
    //

    // Is either AFU making a request?
    logic c0_request_rdy;
    assign c0_request_rdy =
        cci_mpf_c0TxIsValid(c0_afu_pipe[AFU_PIPE_LAST_STAGE]);

    logic c1_request_rdy;
    assign c1_request_rdy =
        cci_mpf_c1TxIsValid(c1_afu_pipe[AFU_PIPE_LAST_STAGE]);

    // Given a request, is the translation ready and can the request be
    // forwarded toward the FIU? TLB miss handler read requests have priority
    // on channel 0. lookupValid will only be set if there was a request.
    logic c0_fwd_req;
    assign c0_fwd_req =
        c0_request_rdy &&
        (tlb_if.lookupValid[0] ||
         ! cci_mpf_c0TxIsReadReq(c0_afu_pipe[AFU_PIPE_LAST_STAGE]) ||
         ! cci_mpf_c0_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
        ! fiu.c0TxAlmFull;

    logic c1_fwd_req;
    assign c1_fwd_req =
        c1_request_rdy &&
        (tlb_if.lookupValid[1] ||
         ! cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LAST_STAGE]) ||
         ! cci_mpf_c1_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr)) &&
        ! fiu.c1TxAlmFull;

    // Did a request miss in the TLB or fail arbitration?  It will be rotated
    // back to the head of afu_pipe.
    logic c0_retry_req;
    assign c0_retry_req = c0_request_rdy && ! c0_fwd_req;

    logic c1_retry_req;
    assign c1_retry_req = c1_request_rdy && ! c1_fwd_req;


    //
    // Manage new requests coming from the AFU.
    //

    logic c0_new_req;
    assign c0_new_req = cci_mpf_c0TxIsValid(afu_buf.c0Tx);

    logic c1_new_req;
    assign c1_new_req = cci_mpf_c1TxIsValid(afu_buf.c1Tx);


    // Is there a WrFence request coming in on channel 1?  Since
    // the pipeline may reorder requests, all pending requests on
    // the channel 1 pipeline must drain before the fence can
    // proceed.
    logic c1_block_wrfence;

    logic c1_afu_pipe_has_valid;
    logic c1_afu_pipe_has_valid_next;

    // Block if the next request is a WrFence and there is a pending write
    assign c1_block_wrfence = c1_afu_pipe_has_valid &&
                              cci_mpf_c1TxIsWriteFenceReq(afu_buf.c1Tx);

    always_comb
    begin
        c1_afu_pipe_has_valid_next = 1'b0;

        for (int i = 0; i <= AFU_PIPE_LAST_STAGE; i = i + 1)
        begin
            c1_afu_pipe_has_valid_next = c1_afu_pipe_has_valid_next ||
                                         c1_afu_pipe[i].valid;
        end
    end

    always_ff @(posedge clk)
    begin
        // Use the conservative test here that afu_buf.c1Tx is a write
        // instead of the real test that deqC1Tx fired since afu_buf.c1Tx
        // has a shorter dependence path and correctly predicts whether
        // the next request after afu_buf.c1Tx should block if it is a
        // WrFence.
        c1_afu_pipe_has_valid <= c1_afu_pipe_has_valid_next ||
                                 cci_mpf_c1TxIsWriteReq(afu_buf.c1Tx);
    end


    // Pass new requests to the afu_pipe?  Old retries have priority over
    // new requests.
    assign deqC0Tx = c0_new_req && ! c0_retry_req;
    assign deqC1Tx = c1_new_req && ! c1_retry_req && ! c1_block_wrfence;


    //
    // Advance the pipeline
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            for (int i = 0; i <= AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i] <= cci_mpf_c0Tx_clearValids();
                c1_afu_pipe[i] <= cci_mpf_c1Tx_clearValids();
            end
        end
        else
        begin
            // All but first two stages are a simple systolic pipeline
            for (int i = 1; i < AFU_PIPE_LAST_STAGE; i = i + 1)
            begin
                c0_afu_pipe[i+1] <= c0_afu_pipe[i];
                c1_afu_pipe[i+1] <= c1_afu_pipe[i];
            end

            // Ready to accept new entries?
            if (! c0_retry_req)
            begin
                c0_afu_pipe[0] <= afu_buf.c0Tx;
            end

            if (! c1_retry_req)
            begin
                // Channel 1 is more complicated because it must block when
                // a WrFence is arriving until this pipeline is quiet.
                c1_afu_pipe[0].hdr   <= afu_buf.c1Tx.hdr;
                c1_afu_pipe[0].data  <= afu_buf.c1Tx.data;
                c1_afu_pipe[0].valid <= afu_buf.c1Tx.valid && ! c1_block_wrfence;
            end

            // Rotate failed lookup or advance pipeline?
            c0_afu_pipe[AFU_PIPE_RETRY_STAGE] <=
                c0_retry_req ? c0_afu_pipe[AFU_PIPE_LAST_STAGE] :
                               c0_afu_pipe[0];

            c1_afu_pipe[AFU_PIPE_RETRY_STAGE] <=
                c1_retry_req ? c1_afu_pipe[AFU_PIPE_LAST_STAGE] :
                               c1_afu_pipe[0];
        end
    end


    //
    // Tap afu_pipe to request translation from the TLB.  Translation is
    // skipped if the incoming request already has a physical address.
    //
    assign tlb_if.lookupPageVA[0] =
        vtp4kbPageIdxFromVA(cci_mpf_c0_getReqAddr(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr));
    assign tlb_if.lookupEn[0] =
        tlb_if.lookupRdy[0] &&
        cci_mpf_c0TxIsReadReq(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE]) &&
        cci_mpf_c0_getReqAddrIsVirtual(c0_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr);

    assign tlb_if.lookupPageVA[1] =
        vtp4kbPageIdxFromVA(cci_mpf_c1_getReqAddr(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr));
    assign tlb_if.lookupEn[1] =
        tlb_if.lookupRdy[1] &&
        cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE]) &&
        cci_mpf_c1_getReqAddrIsVirtual(c1_afu_pipe[AFU_PIPE_LOOKUP_STAGE].hdr);


    // ====================================================================
    //
    //  Requests
    //
    // ====================================================================

    // Construct the read request header.
    t_cci_mpf_c0_ReqMemHdr c0_req_hdr;
    t_tlb_2mb_page_offset c0_req_offset;

    always_comb
    begin
        c0_req_hdr = c0_afu_pipe[AFU_PIPE_LAST_STAGE].hdr;

        // Request's line offset within the page.
        c0_req_offset = vtp2mbPageOffsetFromVA(c0_req_hdr.base.address);

        // Replace the address with the physical address
        if (cci_mpf_c0_getReqAddrIsVirtual(c0_req_hdr))
        begin
            // Page offset remains the same in VA and PA
            c0_req_hdr.base.address = { vtp4kbTo2mbPA(tlb_if.lookupRspPagePA[0]),
                                        c0_req_offset };
            c0_req_hdr.ext.addrIsVirtual = 0;
        end
    end

    // Update channel 0 header with translated address (writes) or pass
    // through original request (interrupt).
    always_ff @(posedge clk)
    begin
        fiu.c0Tx <= cci_mpf_c0TxMaskValids(c0_afu_pipe[AFU_PIPE_LAST_STAGE],
                                           c0_fwd_req);

        // Is the header rewritten for a virtually addressed write?
        if (cci_mpf_c0TxIsReadReq(c0_afu_pipe[AFU_PIPE_LAST_STAGE]))
        begin
            fiu.c0Tx.hdr <= c0_req_hdr;
        end
    end


    // Channel 1 request logic
    t_cci_mpf_c1_ReqMemHdr c1_req_hdr;
    t_tlb_2mb_page_offset c1_req_offset;

    always_comb
    begin
        c1_req_hdr = c1_afu_pipe[AFU_PIPE_LAST_STAGE].hdr;

        // Request's line offset within the page.
        c1_req_offset = vtp2mbPageOffsetFromVA(c1_req_hdr.base.address);

        // Replace the address with the physical address
        if (cci_mpf_c1_getReqAddrIsVirtual(c1_req_hdr))
        begin
            c1_req_hdr.base.address = { vtp4kbTo2mbPA(tlb_if.lookupRspPagePA[1]),
                                        c1_req_offset };
            c1_req_hdr.ext.addrIsVirtual = 0;
        end
    end

    // Update channel 1 header with translated address (writes) or pass
    // through original request (interrupt).
    always_ff @(posedge clk)
    begin
        fiu.c1Tx <= cci_mpf_c1TxMaskValids(c1_afu_pipe[AFU_PIPE_LAST_STAGE],
                                           c1_fwd_req);

        // Is the header rewritten for a virtually addressed write?
        if (cci_mpf_c1TxIsWriteReq(c1_afu_pipe[AFU_PIPE_LAST_STAGE]))
        begin
            fiu.c1Tx.hdr <= c1_req_hdr;
        end
    end


    // ====================================================================
    //
    //  Responses
    //
    // ====================================================================

    assign afu_buf.c0Rx = fiu.c0Rx;
    assign afu_buf.c1Rx = fiu.c1Rx;


    // ====================================================================
    //
    // Channel 2 Tx (MMIO read response) flows straight through.
    //
    // ====================================================================

    assign fiu.c2Tx = afu_buf.c2Tx;

endmodule // cci_mpf_shim_vtp_pipe
