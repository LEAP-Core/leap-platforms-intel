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

`ifndef __CCI_MPF_SHIM_VTP_VH__
`define __CCI_MPF_SHIM_VTP_VH__


`include "cci_mpf_shim_vtp_params.h"

// Index of an aligned physical page
typedef logic [CCI_PT_PA_IDX_BITS-1 : 0] t_tlb_physical_idx;

// Address hash index in the host memory page table
typedef logic [CCI_PT_VA_IDX_BITS-1 : 0] t_pte_va_hash_idx;

// Index (pointer) to line in the page table
typedef logic [CCI_PT_LINE_IDX_BITS-1 : 0] t_pte_idx;

// Address of a virtual page without the page offset bits
typedef logic [CCI_PT_VA_BITS-CCI_PT_PAGE_OFFSET_BITS-1 : 0] t_tlb_va_page;



//
// Interface for TLB lookup.
//
interface cci_mpf_shim_vtp_tlb_if;
    // Look up VA in the table and return the PA or signal a miss two cycles
    // later.  The TLB code operates on aligned pages.  It is up to the caller
    // to compute offsets into pages.
    t_tlb_va_page lookupPageVA[0:1];
    logic lookupEn[0:1];         // Enable the request
    logic lookupRdy[0:1];        // Ready to accept a request?

    // Respond with page's physical address two cycles after lookupEn
    t_tlb_physical_idx lookupRspPagePA[0:1];
    // Signal lookupValid two cycles after lookupEn if the page
    // isn't currently in the FPGA-side translation table.
    logic lookupValid[0:1];


    //
    // Signals for handling misses and fills.
    //
    logic lookupMiss[0:1];
    t_tlb_va_page lookupMissVA[0:1];

    logic fillEn;
    t_tlb_va_page fillVA;
    t_tlb_physical_idx fillPA;
    logic fillRdy;

    modport server
       (
        input  lookupPageVA,
        input  lookupEn,
        output lookupRdy,

        output lookupRspPagePA,
        output lookupValid,

        output lookupMiss,
        output lookupMissVA,
        input  fillEn,
        input  fillVA,
        input  fillPA,
        output fillRdy
        );

    modport client
       (
        output lookupPageVA,
        output lookupEn,
        input  lookupRdy,

        input  lookupRspPagePA,
        input  lookupValid
        );

    // Fill -- add a new translation
    modport fill
       (
        output fillEn,
        output fillVA,
        output fillPA,
        input  fillRdy
        );

endinterface

`endif // __CCI_MPF_SHIM_VTP_VH__
