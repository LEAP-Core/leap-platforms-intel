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

`include "cci_mpf_shim_vtp.vh"


//
// Page table walker for handling virtual to physical TLB misses.
//
// The walker receives requests from the TLB when a translation is not present
// in the TLB.
//
// The table being walked is constructed by software.  The format is
// is described in SW/src/cci_mpf_shim_vtp_pt.cpp.
//
module cci_mpf_shim_vtp_pt_walk
  #(
    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    // CSRs
    cci_mpf_csrs.vtp csrs,

    // Request a page walk.
    input  logic walkPtReqEn,                  // Enable PT walk request
    input  t_tlb_4kb_va_page_idx walkPtReqVA,  // VA to translate
    output logic walkPtReqRdy,                 // Ready to accept a request?

    // Completed a page walk.  Tell the TLB about a new translation
    cci_mpf_shim_vtp_tlb_if.fill tlb_fill_if,

    // Requested VA is not in the page table.  This is an error!
    output logic notPresent,

    // Initiate request to read a line from the shared-memory page table.
    // This is the mechanism by which page table entries are read for
    // the table walk.  Code that instantiates this module is responsible
    // for turning the request into a read of the page table and forwarding
    // the result to ptReadData.
    output logic ptReadEn,
    output t_cci_clAddr ptReadAddr,
    // System ready to accept a read request?
    input  logic ptReadRdy,

    // Response to page table read request
    input t_cci_clData ptReadData,
    input logic ptReadDataEn,

    // Statistics
    output logic statBusy
    );

    initial begin
        // Confirm that the VA size specified in VTP matches CCI.  The CCI
        // version is line addresses, so the units must be converted.
        assert (CCI_MPF_CLADDR_WIDTH + $clog2(CCI_CLDATA_WIDTH >> 3) ==
                48) else
            $fatal("cci_mpf_shim_vtp.sv: VA address size mismatch!");
    end

    // Root address of the page table
    t_cci_clAddr page_table_root;
    assign page_table_root = csrs.vtp_in_page_table_base;

    logic initialized;
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            initialized <= 1'b0;
        end
        else
        begin
            initialized <= csrs.vtp_in_page_table_base_valid &&
                           csrs.vtp_in_mode.enabled;
        end
    end


    // ====================================================================
    //
    //   Page table properties.
    //
    // ====================================================================

    // Hierarchical page table is composed of 4KB pages, each with 512
    // 64 bit pointers either to the translated PA or to the next page
    // in the page table.  Each index is thus 9 bits.
    localparam PT_PAGE_IDX_WIDTH = 9;

    // Page index components: line address and word within line
    localparam PT_PAGE_WORD_IDX_WIDTH = $clog2(CCI_CLDATA_WIDTH / 64);
    typedef logic [PT_PAGE_WORD_IDX_WIDTH-1 : 0] t_pt_page_word_idx;

    localparam PT_PAGE_LINE_IDX_WIDTH = PT_PAGE_IDX_WIDTH - PT_PAGE_WORD_IDX_WIDTH;
    typedef logic [PT_PAGE_LINE_IDX_WIDTH-1 : 0] t_pt_page_line_idx;

    typedef struct packed
    {
        // Index of a line within a 4KB page table
        t_pt_page_line_idx line_idx;
        // Index of a word within the line
        t_pt_page_word_idx word_idx;
    }
    t_pt_page_idx;

    localparam PT_MAX_DEPTH = 4;
    typedef logic [$clog2(PT_MAX_DEPTH)-1 : 0] t_pt_walk_depth;

    function automatic t_pt_page_line_idx ptPageLineIdx(
        t_tlb_4kb_va_page_idx pidx_4k
        );

        // Top bits
        t_pt_page_idx pidx = pidx_4k[$bits(pidx_4k)-1 -: $bits(t_pt_page_idx)];

        return pidx.line_idx;
    endfunction

    function automatic t_pt_page_word_idx ptLineWordIdx(
        t_tlb_4kb_va_page_idx pidx_4k
        );

        // Top bits
        t_pt_page_idx pidx = pidx_4k[$bits(pidx_4k)-1 -: $bits(t_pt_page_idx)];

        return pidx.word_idx;
    endfunction


    // ====================================================================
    //
    //   Page walker state machine.
    //
    // ====================================================================

    typedef enum logic [2:0]
    {
        STATE_PT_WALK_IDLE,
        STATE_PT_WALK_READ_REQ,
        STATE_PT_WALK_READ_WAIT_RSP,
        STATE_PT_WALK_READ_RSP,
        STATE_PT_WALK_DONE,
        STATE_PT_WALK_ERROR
    }
    t_state_pt_walk;

    t_state_pt_walk state;


    //
    // The miss handler supports processing only one request at a time.
    //
    assign walkPtReqRdy = initialized && (state == STATE_PT_WALK_IDLE);

    assign statBusy = (state != STATE_PT_WALK_IDLE);


    // Base address of current page being accessed.  During a walk pt_cur_page
    // points to pages in the page table.  When translation is complete it
    // points to the translated physical page.
    t_cci_clAddr pt_walk_cur_page;

    typedef struct
    {
        // Terminal entry found (the translation)
        logic success;

        // Translation error (no translation found)
        logic error;
    }
    t_pt_walk_status;

    function automatic t_pt_walk_status pt_walk_word_to_status(logic [63:0] w);
        t_pt_walk_status s;

        // Bit 0 in the response word indicates a successful translation.
        s.success = w[0];

        // The SW initializes entries to ~0.  Check bit 1 as a proxy for
        // the entire entry being invalid.
        s.error = w[1];

        return s;
    endfunction

    t_pt_walk_status pt_walk_cur_status;

    // Selected word within the response line
    logic [63 : 0] pt_read_rsp_word;

    // VA being translated
    t_tlb_4kb_va_page_idx translate_va;

    // During translation the VA is broken down into 9 bit indices during
    // the tree-based page walk.  This register is shifted as each level
    // is traversed, leaving the next index in the high bits.
    t_tlb_4kb_va_page_idx translate_va_idx;

    // Record the word in the line requested in the most recent page table
    // read.
    t_pt_page_word_idx translate_va_prev_word_idx;
    

    // Track the depth while walking the table.  This is one way of detecting
    // a malformed table or missing entry.
    t_pt_walk_depth translate_depth;

    //
    // State transition.  One request is processed at a time.
    //
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_PT_WALK_IDLE;
            notPresent <= 1'b0;
        end
        else
        begin
            case (state)
              STATE_PT_WALK_IDLE:
                begin
                    // New request arrived and not already doing a walk
                    if (walkPtReqEn)
                    begin
                        state <= STATE_PT_WALK_READ_REQ;
                    end

                    // New request
                    translate_va <= walkPtReqVA;
                    translate_va_idx <= walkPtReqVA;
                    translate_depth <= t_pt_walk_depth'(~0);

                    pt_walk_cur_page <= page_table_root;
                end

              STATE_PT_WALK_READ_REQ:
                begin
                    // Wait until a PT read request can fire
                    if (ptReadEn)
                    begin
                        state <= STATE_PT_WALK_READ_WAIT_RSP;

                        translate_va_prev_word_idx <= ptLineWordIdx(translate_va_idx);

                        // Read requested from a level of the page table.
                        // Shift to move to the index of the next level.
                        translate_va_idx <=
                            t_tlb_4kb_va_page_idx'({ translate_va_idx,
                                                     PT_PAGE_IDX_WIDTH'('x) });
                        translate_depth <= translate_depth + t_pt_walk_depth'(1);
                    end
                end

              STATE_PT_WALK_READ_WAIT_RSP:
                begin
                    // Wait for PT read response
                    if (ptReadDataEn)
                    begin
                        state <= STATE_PT_WALK_READ_RSP;

                        pt_walk_cur_status <= pt_walk_word_to_status(pt_read_rsp_word);

                        // Extract the address of a line from the entry.
                        pt_walk_cur_page <=
                            pt_read_rsp_word[$clog2(CCI_CLDATA_WIDTH / 8) +:
                                             CCI_CLADDR_WIDTH];
                    end
                end

              STATE_PT_WALK_READ_RSP:
                begin
                    // Raise an error if the maximum walk depth is reached without
                    // finding the entry.
                    if (pt_walk_cur_status.error || 
                        ! pt_walk_cur_status.success && (&(translate_depth) == 1'b1))
                    begin
                        state <= STATE_PT_WALK_ERROR;
                    end
                    else if (pt_walk_cur_status.success)
                    begin
                        // Found the translation
                        state <= STATE_PT_WALK_DONE;
                    end
                    else
                    begin
                        // Continue the walk
                        state <= STATE_PT_WALK_READ_REQ;
                    end
                end

              STATE_PT_WALK_DONE:
                begin
                    // Current request is complete
                    if (tlb_fill_if.fillEn)
                    begin
                        state <= STATE_PT_WALK_IDLE;
                    end
                end

              STATE_PT_WALK_ERROR:
                begin
                    // Terminal state
                    notPresent <= 1'b1;
                end
            endcase
        end
    end


    // ====================================================================
    //
    //   Generate page table read requests.
    //
    // ====================================================================

    // Enable a read request?
    assign ptReadEn = (state == STATE_PT_WALK_READ_REQ) && ptReadRdy;

    // Address of read request
    always_comb
    begin
        // Current page in table
        ptReadAddr = pt_walk_cur_page;

        // Select the proper line in this level of the table, based on the
        // portion of the VA corresponding to the level.
        ptReadAddr[PT_PAGE_LINE_IDX_WIDTH-1 : 0] = ptPageLineIdx(translate_va_idx);
    end


    // ====================================================================
    //
    //   Consume page table read responses.
    //
    // ====================================================================

    // Break a read response line into 64 bit words
    logic [(CCI_CLDATA_WIDTH / 64)-1 : 0][63 : 0] pt_read_rsp_word_vec;

    always_comb
    begin
        pt_read_rsp_word_vec = ptReadData;
        pt_read_rsp_word = pt_read_rsp_word_vec[translate_va_prev_word_idx];
    end


    always_ff @(posedge clk)
    begin
        if (! reset && DEBUG_MESSAGES)
        begin
            if (walkPtReqEn && (state == STATE_PT_WALK_IDLE))
            begin
                $display("PT WALK: New req translate line 0x%x (VA 0x%x)",
                         { walkPtReqVA, CCI_PT_4KB_PAGE_OFFSET_BITS'(0) },
                         { walkPtReqVA, CCI_PT_4KB_PAGE_OFFSET_BITS'(0), 6'b0 });
            end

            if (ptReadEn)
            begin
                $display("PT WALK: PTE read addr 0x%x (PA 0x%x) (line 0x%x, word 0x%x)",
                         ptReadAddr, {ptReadAddr, 6'b0},
                         ptPageLineIdx(translate_va_idx),
                         ptLineWordIdx(translate_va_idx));
            end

            if (ptReadDataEn)
            begin
                $display("PT WALK: Line arrived 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x",
                         pt_read_rsp_word_vec[7],
                         pt_read_rsp_word_vec[6],
                         pt_read_rsp_word_vec[5],
                         pt_read_rsp_word_vec[4],
                         pt_read_rsp_word_vec[3],
                         pt_read_rsp_word_vec[2],
                         pt_read_rsp_word_vec[1],
                         pt_read_rsp_word_vec[0]);
            end

            if (tlb_fill_if.fillEn)
            begin
                $display("PT WALK: Response Addr 0x%x (PA 0x%x), size %s",
                         pt_walk_cur_page, {pt_walk_cur_page, 6'b0},
                         (tlb_fill_if.fillBigPage ? "2MB" : "4KB"));
            end

            if ((state == STATE_PT_WALK_ERROR) && ! notPresent)
            begin
                $display("PT WALK: Error!");
            end
        end
    end


    // ====================================================================
    //
    //   Return page walk result.
    //
    // ====================================================================

    //
    // TLB insertion (in STATE_PT_WALK_INSERT)
    //
    assign tlb_fill_if.fillEn = (state == STATE_PT_WALK_DONE) &&
                                tlb_fill_if.fillRdy;
    assign tlb_fill_if.fillVA = translate_va;
    assign tlb_fill_if.fillPA = pt_walk_cur_page[CCI_PT_4KB_PAGE_OFFSET_BITS +:
                                                 CCI_PT_4KB_PA_PAGE_INDEX_BITS];
    // Use just bit 0 of translate_depth, which is either 2 for a 2MB page
    // or 3 for a 4KB page.
    assign tlb_fill_if.fillBigPage = ! (translate_depth[0]);

endmodule // cci_mpf_shim_vtp_pt_walk

