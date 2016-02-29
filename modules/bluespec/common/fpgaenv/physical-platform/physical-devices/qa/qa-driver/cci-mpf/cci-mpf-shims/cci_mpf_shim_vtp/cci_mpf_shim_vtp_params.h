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


// ========================================================================
//
//  This file is included by both C++ and System Verilog.  The syntax
//  must be acceptable to both.
//
// ========================================================================

typedef enum
{
    // Width of a virtual address (byte addresses).  This value must match
    // the width of the CCI request header defined in the base CCI structures.
    CCI_PT_VA_BITS          = 48,

    //
    // Components of a virtual address:
    //

    // Low order zero bits in both VA and PA of a page
    CCI_PT_PAGE_OFFSET_BITS = 21,   // 21 == 2MB pages
    // VA bits used as an index into the shared page table
    CCI_PT_VA_IDX_BITS      = 14,   // 14 == 16K buckets in the hash table
    // The final component of a VA is the tag, used to determine whether
    // an address in the table matches given a matching IDX.  The size
    // of the tag is computed from CCI_PT_VA_BITS and the fields above.

    // Physical page index size.  A physical address is the concatenation
    // of a page index and a page offset, defined above.  NOTE: While
    // the size of a PTE is CCI_PT_VA_TAG_BITS + CCI_PT_PA_IDX_BITS,
    // the table-generation code will round up the PTE size to a multiple
    // of bytes.
    CCI_PT_PA_IDX_BITS      = 17,

    // The page table contains pointers to other lines holding more PTEs
    // associated with the current hash.  Pointers are line offsets from
    // the base of the page table.  The size of this offset determines
    // the maximum size of the page table.
    CCI_PT_LINE_IDX_BITS    = 15    // 15 == 2MB with 64 byte lines
}
t_CCI_MPF_SHIM_VTP_PARAMS;
