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
// Map virtual to physical addresses.
//
// Requests coming from the AFU can be tagged as containing either virtual
// or physical addresses.  Physical addresses are passed directly to the
// FIU without translation here.  The tag is accessed with the
// getReqAddrIsVirtual() function.
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

module cci_mpf_shim_vtp
  #(
    // The TLB needs to generate loads internally in order to walk the
    // page table.  The reserved bit in Mdata is a location offered
    // to the page table walker to tag internal loads.  The Mdata location
    // must be zero on all requests flowing in to the TLB through the
    // afu interface below.
    //
    // Some shims (e.g. cci_mpf_shim_sort_responses) already manage Mdata and
    // guarantee that some high bits will be zero.
    parameter RESERVED_MDATA_IDX = -1,

    parameter AFU_BUF_THRESHOLD = CCI_TX_ALMOST_FULL_THRESHOLD,
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
    cci_mpf_csrs.vtp_events events
    );

    logic reset;
    assign reset = fiu.reset;

    // ====================================================================
    //
    //   Primary virtual to physical translation pipeline.
    //
    // ====================================================================

    cci_mpf_if fiu_pipe (.clk);
    assign fiu_pipe.reset = fiu.reset;

    cci_mpf_shim_vtp_tlb_if tlb_if();

    cci_mpf_shim_vtp_pipe
      #(
        .AFU_BUF_THRESHOLD(AFU_BUF_THRESHOLD),
        .DEBUG_MESSAGES(DEBUG_MESSAGES)
        )
      pipe
       (
        .clk,
        .fiu(fiu_pipe),
        .afu,
        .csrs,
        .tlb_if
        );


    // ====================================================================
    //
    //  TLB
    //
    // ====================================================================

    //
    // Allocate two TLBs.  One manages 4KB pages and the other manages
    // 2MB pages.
    //

    cci_mpf_shim_vtp_tlb_if tlb_if_4kb();

    cci_mpf_shim_vtp_tlb
      #(
        .CCI_PT_PAGE_OFFSET_BITS(CCI_PT_4KB_PAGE_OFFSET_BITS),
        .NUM_TLB_SETS(1024),
        .DEBUG_MESSAGES(DEBUG_MESSAGES),
        .DEBUG_NAME("4KB")
        )
      tlb4kb
       (
        .clk,
        .reset,
        .tlb_if(tlb_if_4kb),
        .csrs
        );


    cci_mpf_shim_vtp_tlb_if tlb_if_2mb();

    cci_mpf_shim_vtp_tlb
      #(
        .CCI_PT_PAGE_OFFSET_BITS(CCI_PT_2MB_PAGE_OFFSET_BITS),
        .NUM_TLB_SETS(512),
        .DEBUG_MESSAGES(DEBUG_MESSAGES),
        .DEBUG_NAME("2MB")
        )
      tlb2mb
       (
        .clk,
        .reset,
        .tlb_if(tlb_if_2mb),
        .csrs
        );

    genvar p;
    generate
        for (p = 0; p < 2; p = p + 1)
        begin : tlb_ports
            // When the pipeline requests a TLB lookup do it on both pipelines.
            assign tlb_if_4kb.lookupPageVA[p] = tlb_if.lookupPageVA[p];
            assign tlb_if_4kb.lookupEn[p] = tlb_if.lookupEn[p];
            assign tlb_if_2mb.lookupPageVA[p] = tlb_if.lookupPageVA[p];
            assign tlb_if_2mb.lookupEn[p] = tlb_if.lookupEn[p];
            assign tlb_if.lookupRdy[p] = tlb_if_4kb.lookupRdy[p] &&
                                         tlb_if_2mb.lookupRdy[p];

            // The TLB pipeline is fixed length, so responses arrive together.
            // At most one TLB should have a translation for a given address.
            assign tlb_if.lookupValid[p] = tlb_if_4kb.lookupValid[p] ||
                                           tlb_if_2mb.lookupValid[p];
            assign tlb_if.lookupIsBigPage[p] = tlb_if_2mb.lookupValid[p];
            assign tlb_if.lookupRspPagePA[p] =
                tlb_if_4kb.lookupValid[p] ? tlb_if_4kb.lookupRspPagePA[p] :
                                            tlb_if_2mb.lookupRspPagePA[p];

            // Read the page table if both TLBs miss
            assign tlb_if.lookupMiss[p] = tlb_if_4kb.lookupMiss[p] &&
                                          tlb_if_2mb.lookupMiss[p];
            assign tlb_if.lookupMissVA[p] = tlb_if_4kb.lookupMissVA[p];

            // Validation
            always_ff @(posedge clk)
            begin
                if (! reset)
                begin
                    assert(! tlb_if_4kb.lookupValid[p] || ! tlb_if_2mb.lookupValid[p]) else
                        $fatal("cci_mpf_shim_vtp: Both TLBs valid!");

                    if (tlb_if.lookupMiss[p])
                    begin
                        assert(vtp4kbTo2mbVA(tlb_if_4kb.lookupMissVA[p]) ==
                               vtp4kbTo2mbVA(tlb_if_2mb.lookupMissVA[p])) else
                            $fatal("cci_mpf_shim_vtp: Both TLBs missed but addresses different!");
                    end
                end
            end
        end
    endgenerate

    // Direct fills to the appropriate TLB depending on the page size
    assign tlb_if_4kb.fillEn = tlb_if.fillEn && ! tlb_if.fillBigPage;
    assign tlb_if_2mb.fillEn = tlb_if.fillEn && tlb_if.fillBigPage;

    assign tlb_if_4kb.fillVA = tlb_if.fillVA;
    assign tlb_if_4kb.fillPA = tlb_if.fillPA;
    assign tlb_if_2mb.fillVA = tlb_if.fillVA;
    assign tlb_if_2mb.fillPA = tlb_if.fillPA;
    assign tlb_if.fillRdy = tlb_if_4kb.fillRdy && tlb_if_2mb.fillRdy;

    // Statistics
    always_comb
    begin
        events.vtp_out_event_4kb_hit_c0 = tlb_if_4kb.lookupValid[0];
        events.vtp_out_event_4kb_hit_c1 = tlb_if_4kb.lookupValid[1];

        events.vtp_out_event_2mb_hit_c0 = tlb_if_2mb.lookupValid[0];
        events.vtp_out_event_2mb_hit_c1 = tlb_if_2mb.lookupValid[1];

        events.vtp_out_event_4kb_miss = tlb_if_4kb.fillEn;
        events.vtp_out_event_2mb_miss = tlb_if_2mb.fillEn;
    end


    // ====================================================================
    //
    //   Page walker.
    //
    // ====================================================================

    logic walk_pt_rdy;
    logic walk_pt_req_en;
    t_tlb_4kb_va_page_idx walk_pt_req_va[0 : 1];

    // Miss channel arbiter -- used for fairness
    logic last_miss_channel;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            last_miss_channel <= 1'b0;
            walk_pt_req_en <= 1'b0;
        end
        else if (walk_pt_req_en)
        begin
            // New request forwarded to page walker
            walk_pt_req_en <= 0;
        end
        else
        begin
            //
            // Did one of the channels miss?  Use the last_miss_channel
            // arbiter to alternate between channels.
            //
            // In addition to the page walker being ready we also require
            // that the TLB be ready to fill. This is done solely to handle
            // a corner case in which the TLB is processing a fill to the
            // same address that is signalling a miss. Processing the fill
            // would be technically correct but wasteful, since the
            // translation will be added to the TLB within a few cycles.
            //
            if (walk_pt_req_en || ! walk_pt_rdy || ! tlb_if.fillRdy)
            begin
                walk_pt_req_en <= 0;
            end
            else if (tlb_if.lookupMiss[0] &&
                     ((last_miss_channel == 1) || ! tlb_if.lookupMiss[1]))
            begin
                walk_pt_req_en <= 1;
                last_miss_channel <= 0;
            end
            else if (tlb_if.lookupMiss[1])
            begin
                walk_pt_req_en <= 1;
                last_miss_channel <= 1;
            end
        end
    end

    always_ff @(posedge clk)
    begin
        walk_pt_req_va[0] <= tlb_if.lookupMissVA[0];
        walk_pt_req_va[1] <= tlb_if.lookupMissVA[1];
    end

    always_ff @(posedge clk)
    begin
        if (! reset && walk_pt_req_en && DEBUG_MESSAGES)
        begin
            $display("VTP: Request page walk for miss chan %0d, VA 0x%x",
                     last_miss_channel,
                     {walk_pt_req_va[last_miss_channel], CCI_PT_4KB_PAGE_OFFSET_BITS'(0)});
        end
    end

    // Not present is an error signal. It means that the VA is not present
    // in the host-memory PTE.
    logic notPresent;

    always_ff @(posedge clk)
    begin
        if (! reset)
        begin
            assert (! notPresent) else
                $fatal("cci_mpf_shim_vtp: VA not present in page table");
        end
    end


    // Page table read request and response signals
    logic ptReadEn;
    logic ptReadEn_q;
    t_cci_clAddr ptReadAddr;
    t_cci_clAddr ptReadAddr_q;
    logic ptReadDataEn;

    cci_mpf_shim_vtp_pt_walk
      #(
        .DEBUG_MESSAGES(DEBUG_MESSAGES)
        )
      walker
       (
        .clk,
        .reset,

        .csrs,

        .walkPtReqEn(walk_pt_req_en),
        .walkPtReqVA(walk_pt_req_va[last_miss_channel]),
        .walkPtReqRdy(walk_pt_rdy),

        .tlb_fill_if(tlb_if),

        .notPresent,

        .ptReadEn,
        .ptReadAddr,
        .ptReadRdy(! ptReadEn_q),

        .ptReadData(fiu.c0Rx.data),
        .ptReadDataEn,

        .statBusy(events.vtp_out_event_pt_walk_busy)
        );


    // ====================================================================
    //
    //   Connection to FIU.
    //
    // ====================================================================

    //
    // Most connections flow as simple wires between the external fiu
    // connection and fiu_pipe, coming from the primary translation
    // pipeline declared above.  The exception is page walker requests,
    // which are injected on the c0Tx read request and consumed on the
    // c0Rx read response channels.
    //

    t_if_cci_mpf_c0_Tx fiu_c0Tx;
    t_cci_mpf_c0_ReqMemHdr c0_req_hdr;
    logic did_pt_rd;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            ptReadEn_q <= 1'b0;
        end
        else
        begin
            // Request to read from the page table is held in the register
            // until it is processed.  Processing may be delayed by traffic
            // through fiu_pipe.c0Tx.  c0TxAlmFull is asserted when a page
            // table read is needed, so did_pt_rd will be true soon after
            // the page table read request arrives.
            if (did_pt_rd || ! ptReadEn_q)
            begin
                ptReadEn_q <= ptReadEn;
                ptReadAddr_q   <= ptReadAddr;
            end
        end
    end

    always_comb
    begin
        // Give priority to page table walker read requests.
        fiu_pipe.c0TxAlmFull = fiu.c0TxAlmFull || ptReadEn_q;

        // Normal read
        fiu_c0Tx = fiu_pipe.c0Tx;
        did_pt_rd = 1'b0;

        if (! cci_mpf_c0TxIsValid(fiu_pipe.c0Tx) && ptReadEn_q &&
            ! fiu.c0TxAlmFull)
        begin
            //
            // Read for TLB miss.
            //
            did_pt_rd = 1'b1;
            c0_req_hdr = cci_mpf_c0_genReqHdr(eREQ_RDLINE_S,
                                              ptReadAddr_q,
                                              t_cci_mdata'(0),
                                              cci_mpf_defaultReqHdrParams(0));

            // Tag the request as a local page table walk
            c0_req_hdr[RESERVED_MDATA_IDX] = 1'b1;
            fiu_c0Tx = cci_mpf_genC0TxReadReq(c0_req_hdr, 1'b1);
        end
    end

    always_ff @(posedge clk)
    begin
        fiu.c0Tx <= fiu_c0Tx;
    end

    assign fiu.c1Tx = fiu_pipe.c1Tx;
    assign fiu_pipe.c1TxAlmFull = fiu.c1TxAlmFull;

    assign fiu.c2Tx = fiu_pipe.c2Tx;

    // Is the read response an internal page table reference?
    logic is_pt_rsp;
    assign is_pt_rsp = fiu.c0Rx.hdr[RESERVED_MDATA_IDX];

    always_comb
    begin
        fiu_pipe.c0Rx = fiu.c0Rx;

        // Is the read response for the page table walker?
        ptReadDataEn = cci_c0Rx_isReadRsp(fiu.c0Rx) && is_pt_rsp;

        // Only forward client-generated read responses
        fiu_pipe.c0Rx.rspValid = fiu.c0Rx.rspValid && ! ptReadDataEn;
    end

    assign fiu_pipe.c1Rx = fiu.c1Rx;


    //
    // Validate parameter settings and that the Mdata reserved bit is 0
    // on all incoming read requests.
    //
    always_ff @(posedge clk)
    begin
        assert ((RESERVED_MDATA_IDX > 0) && (RESERVED_MDATA_IDX < CCI_MDATA_WIDTH)) else
            $fatal("cci_mpf_shim_vtp.sv: Illegal RESERVED_MDATA_IDX value: %d", RESERVED_MDATA_IDX);

        if (! reset)
        begin
            assert((fiu_pipe.c0Tx.hdr[RESERVED_MDATA_IDX] == 0) ||
                   ! fiu_pipe.c0Tx.valid) else
                $fatal("cci_mpf_shim_vtp.sv: AFU C0 Mdata[%d] must be zero", RESERVED_MDATA_IDX);
        end
    end

endmodule // cci_mpf_shim_vtp
