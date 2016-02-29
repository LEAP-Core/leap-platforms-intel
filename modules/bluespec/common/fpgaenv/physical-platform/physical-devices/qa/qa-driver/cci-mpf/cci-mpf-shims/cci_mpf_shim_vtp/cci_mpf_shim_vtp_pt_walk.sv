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
module cci_mpf_shim_vtp_pt_walk
  #(
    parameter DEBUG_MESSAGES = 0
    )
   (
    input  logic clk,
    input  logic reset,

    // Request a page walk.
    input  logic walkPtReqEn,              // Enable PT walk request
    input  t_tlb_va_page walkPtReqVA,      // VA to translate
    output logic walkPtReqRdy,             // Ready to accept a request?

    // Completed a page walk.  Tell the TLB about a new translation
    cci_mpf_shim_vtp_tlb_if.fill tlb_fill_if,

    // Requested VA is not in the page table.  This is an error!
    output logic notPresent,

    // Initiate request to read a line from the shared-memory page table.
    // This is the mechanism by which page table entries are read for
    // the table walk.  Code that instantiates this module is responsible
    // for turning the request into a read of the page table and forwarding
    // the result to ptReadData.
    output logic ptReadIdxEn,
    output t_pte_idx ptReadIdx,
    // System ready to accept a read request?
    input  logic ptReadIdxRdy,

    // Response to page table read request
    input t_cci_clData ptReadData,
    input logic ptReadDataEn
    );

    // Address tag in the page table (tag concatenated with hash index is
    // the virtual page.
    localparam CCI_PT_VA_TAG_BITS = CCI_PT_VA_BITS -
                                    CCI_PT_VA_IDX_BITS -
                                    CCI_PT_PAGE_OFFSET_BITS;

    typedef logic [CCI_PT_VA_TAG_BITS-1 : 0] t_pte_va_tag;

    initial begin
        // Confirm that the VA size specified in VTP matches CCI.  The CCI
        // version is line addresses, so the units must be converted.
        assert (CCI_MPF_CLADDR_WIDTH + $clog2(CCI_CLDATA_WIDTH >> 3) ==
                CCI_PT_VA_BITS) else
            $fatal("cci_mpf_shim_vtp.sv: VA address size mismatch!");
    end


    // ====================================================================
    //
    //   Page walker state machine.
    //
    // ====================================================================

    typedef enum logic [2:0]
    {
        STATE_PT_WALK_IDLE,
        STATE_PT_WALK_READ_REQ,
        STATE_PT_WALK_READ_RSP,
        STATE_PT_WALK_SEARCH_LINE,
        STATE_PT_WALK_INSERT
    }
    t_state_pt_walk;

    t_state_pt_walk state;

    // Bytes to hold a single PTE
    localparam PTE_BYTES = (CCI_PT_VA_TAG_BITS + CCI_PT_PA_IDX_BITS + 7) / 8;
    // Bytes to hold a page table pointer
    localparam PT_IDX_BYTES = (CCI_PT_PA_IDX_BITS + 7) / 8;
    // Number of page table entries in a line
    localparam PTES_PER_LINE = ((CCI_CLDATA_WIDTH / 8) - PT_IDX_BYTES) / PTE_BYTES;

    // Buffer for storing the line being searched in the page table
    t_cci_clData pt_line;
    // Counter to track number of PTEs active in pt_line
    logic [PTES_PER_LINE : 0] pte_num;

    // One page table entry
    typedef struct packed
    {
        t_pte_va_tag       vTag;
        t_tlb_physical_idx pIdx;
    }
    t_pte;

    logic error_pte_missing;

    t_pte found_pte;
    t_pte cur_pte;
    assign cur_pte = t_pte'(pt_line);

    t_pte_va_hash_idx pte_hash_idx;
    t_pte_va_tag pte_va_tag;

    t_pte_idx pte_idx;

    //
    // The miss handler supports processing only one request at a time.
    //
    assign walkPtReqRdy = (state == STATE_PT_WALK_IDLE);


    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= STATE_PT_WALK_IDLE;
            error_pte_missing <= 1'b0;
        end
        else
        begin
            case (state)
              STATE_PT_WALK_IDLE:
                begin
                    if (walkPtReqEn)
                    begin
                        state <= STATE_PT_WALK_READ_REQ;
                    end

                    {pte_va_tag, pte_hash_idx} <= walkPtReqVA;

                    // Why the double application of types to walkPtReqVA?
                    // The hash index isolates the proper bits of the page
                    // address in the hash table.  The PTE index type grows
                    // the pointer to the full size index used in the PTE.
                    // (The PTE index space includes both the hash table
                    // and overflow space to which hash entries can point
                    // in order to construct longer linked lists.)
                    pte_idx <= t_pte_idx'(t_pte_va_hash_idx'(walkPtReqVA));
                end

              STATE_PT_WALK_READ_REQ:
                begin
                    //
                    // Request a line from the page table.
                    //
                    if (ptReadIdxRdy)
                    begin
                        state <= STATE_PT_WALK_READ_RSP;
                    end
                end

              STATE_PT_WALK_READ_RSP:
                begin
                    //
                    // Wait for page table line read response.
                    //
                    pt_line <= ptReadData;
                    pte_num <= PTES_PER_LINE;

                    if (ptReadDataEn)
                    begin
                        state <= STATE_PT_WALK_SEARCH_LINE;
                    end
                end

              STATE_PT_WALK_SEARCH_LINE:
                begin
                    //
                    // Iterate over the PTEs in a page table line, looking
                    // for a VA tag match.
                    //
                    if (error_pte_missing)
                    begin
                        // Nothing
                    end
                    else if (pte_num == PTES_PER_LINE'(0))
                    begin
                        // Last PTE in the current line.  Continue along
                        // the linked list of lines.
                        if (t_pte_idx'(pt_line) == t_pte_idx'(0))
                        begin
                            // End of list
                            error_pte_missing <= 1'b1;

                            if (DEBUG_MESSAGES)
                            begin
                                $display("PT WALK: ERROR, failed to find 0x%x",
                                         {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)});
                            end
                        end
                        else
                        begin
                            // Read the next line in the linked list
                            state <= STATE_PT_WALK_READ_REQ;

                            if (DEBUG_MESSAGES)
                            begin
                                $display("PT WALK: Search for 0x%x, next line %0d",
                                         {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                         t_pte_idx'(pt_line));
                            end
                        end
                    end
                    else if (cur_pte.vTag == pte_va_tag)
                    begin
                        // Found the requested PTE!
                        state <= STATE_PT_WALK_INSERT;

                        if (DEBUG_MESSAGES)
                        begin
                            $display("PT WALK: Found 0x%x (PA 0x%x), num %0d",
                                     {cur_pte.vTag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.pIdx, CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     pte_num);
                        end
                    end
                    else
                    begin
                        if (cur_pte.vTag == t_pte_va_tag'(0))
                        begin
                            // NULL VA tag -- no more translations
                            error_pte_missing <= 1'b1;
                        end

                        if (DEBUG_MESSAGES)
                        begin
                            $display("PT WALK: Search for 0x%x, at 0x%x (PA 0x%x), num %0d",
                                     {pte_va_tag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.vTag, pte_hash_idx,  CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     {cur_pte.pIdx, CCI_PT_PAGE_OFFSET_BITS'(0)},
                                     pte_num);
                        end
                    end

                    // Record the found PTE unconditionally.  It will only be
                    // used after transition to STATE_PT_WALK_INSERT.
                    found_pte <= cur_pte;

                    // Shift the line by one PTE so the next iteration
                    // may search the next PTE.  The size of a PTE is
                    // rounded up to a multiple of bytes.  This only matters
                    // when the state remains STATE_PT_WALK_SEARCH_LINE.
                    pt_line <= pt_line >> (8 * (($bits(t_pte) + 7) / 8));
                    pte_num <= pte_num - 1;

                    // Unconditionally update pte_idx in case a new PTE entry
                    // must be read from host memory. This will only be used
                    // if the state changes back to STATE_PT_WALK_READ_REQ in the
                    // code above.
                    pte_idx <= t_pte_idx'(pt_line);
                end

              STATE_PT_WALK_INSERT:
                begin
                    // The translation is added to the TLB.
                    if (tlb_fill_if.fillRdy)
                    begin
                        state <= STATE_PT_WALK_IDLE;
                    end
                end
            endcase
        end
    end

    // Request a page table read depending on state.
    assign ptReadIdx = pte_idx;
    assign ptReadIdxEn = ptReadIdxRdy && (state == STATE_PT_WALK_READ_REQ);

    always_ff @(posedge clk)
    begin
        if (! reset && DEBUG_MESSAGES)
        begin
            if (ptReadIdxEn)
            begin
                $display("PT WALK: PTE read idx 0x%x", ptReadIdx);
            end
        end
    end

    // Signal an error
    assign notPresent = error_pte_missing;

    //
    // TLB insertion (in STATE_PT_WALK_INSERT)
    //
    assign tlb_fill_if.fillEn = (state == STATE_PT_WALK_INSERT) &&
                                tlb_fill_if.fillRdy;
    assign tlb_fill_if.fillVA = {pte_va_tag, pte_hash_idx};
    assign tlb_fill_if.fillPA = found_pte.pIdx;

endmodule // cci_mpf_shim_vtp_pt_walk

