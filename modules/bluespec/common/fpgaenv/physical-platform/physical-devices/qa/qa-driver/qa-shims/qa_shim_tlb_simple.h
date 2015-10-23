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
//

#ifndef QA_SHIM_TLB_SIMPLE_H
#define QA_SHIM_TLB_SIMPLE_H

// AAL redefines ASSERT and TRACE
#undef ASSERT
#undef TRACE

#include <time.h>
#include <vector>

#include <aalsdk/AAL.h>

USING_NAMESPACE(std)
USING_NAMESPACE(AAL)

//
// All configuration parameters are defined in this include file.  The
// file is legal C and System Verilog syntax.
//
#include "qa_shim_tlb_simple_params.h"

//
// The shared page table is stored in a contiguous region of physical memory.
// The table is a hashed structure, with CCI_PT_VA_IDX_BITS buckets.  Each bucket
// is a single CCI memory line holding a ptesPerLine length vector of
// CCI_PT_PTEs.  ptesPerLine must be set such that it leaves room for
// a pointer of size CCI_PT_OFFSET_BITS in the high bits of the bucket for
// the next pointer.  The next pointer is used when the number of PTEs overflows
// a hash bucket.
//
//      MSB                                                        0
//     --------------------------------------------------------------
//     | next ptr |   PTE   |   PTE   |   PTE   |   PTE   |   PTE   |
//     --------------------------------------------------------------
//
// The initial bucket for a given VA is found at the idx field of a VA, defined
// below.  The index is the line offset from the root of the page table.
// When the number of PTEs in a bucket overflows the available space
// the table may be extended by setting next ptr to a line offset of another
// bucket in the page table.  The offset must be beyond the hash buckets
// defined by CCI_PT_VA_IDX_BITS.
//
// The entire page table starts initialized to zero.  A PTE holding a virtual
// offset 0 is assumed to be NULL and terminates a list.  The next ptr value
// 0 also terminates a list.
//


typedef class QA_SHIM_TLB_CLASS* QA_SHIM_TLB;
typedef class AFU_CLIENT_CLASS* AFU_CLIENT;


class QA_SHIM_TLB_CLASS : public CAASBase
{
  public:
    QA_SHIM_TLB_CLASS(AFU_CLIENT afuClient);
    ~QA_SHIM_TLB_CLASS();

    //
    // Allocate a memory buffer shared by the host and an FPGA.
    //
    void* CreateSharedBufferInVM(size_t size_bytes);
    void FreeSharedBuffer(void* va);

    // Virtual to physical translation for allocated objects
    btPhysAddr SharedBufferVAtoPA(const void* va);

  private:
    //
    // Add a new page to the table.
    //
    void InsertPageMapping(const void* va, btPhysAddr pa);

    //
    // Convert addresses to their component bit ranges
    //
    inline void AddrComponentsFromVA(uint64_t va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);
    
    inline void AddrComponentsFromVA(const void* va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);
    
    inline void AddrComponentsFromPA(uint64_t pa,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);

    //
    // Construct a PTE from a virtual/physical address pair.
    //
    inline uint64_t AddrToPTE(uint64_t va, uint64_t pa);
    inline uint64_t AddrToPTE(const void* va, uint64_t pa);

    //
    // Read a PTE or table index currently in the table.
    //
    void ReadPTE(const uint8_t* pte, uint64_t& vaTag, uint64_t& paIdx);
    uint64_t ReadTableIdx(const uint8_t* p);

    //
    // Read a PTE or table index to the table.
    //
    void WritePTE(uint8_t* pte, uint64_t vaTag, uint64_t paIdx);
    void WriteTableIdx(uint8_t* p, uint64_t idx);

    // Dump the page table (debugging)
    void DumpPageTable();

    const size_t pageSize = MB(2);
    const size_t pageMask = ~(pageSize - 1);

    // Size of a single PTE.  PTE is a tuple: VA tag and PA page index.
    // The size is rounded up to a multiple of bytes.
    const uint32_t pteBytes = (CCI_PT_VA_TAG_BITS + CCI_PT_PA_IDX_BITS + 7) / 8;

    // Size of a page table pointer rounded up to a multiple of bytes
    const uint32_t ptIdxBytes = (CCI_PT_PA_IDX_BITS + 7) / 8;

    // Number of PTEs that fit in a line.  A line is the basic entry in
    // the hash table.  It holds as many PTEs as fit and ends with a pointer
    // to the next line, where the list of PTEs continues.
    const uint32_t ptesPerLine = (CL(1) - ptIdxBytes) / pteBytes;

    uint8_t*       m_pageTable;
    btPhysAddr     m_pageTablePA;

    uint8_t*       m_pageTableEnd;      // First address beyond the page table
    uint8_t*       m_pageTableFree;     // First free line in the page table

    AFU_CLIENT     m_afuClient;
};


inline void
QA_SHIM_TLB_CLASS::AddrComponentsFromVA(
    uint64_t va,
    uint64_t& tag,
    uint64_t& idx,
    uint64_t& byteOffset)
{
    uint64_t v = va;

    byteOffset = v & ((1LL << CCI_PT_PAGE_OFFSET_BITS) - 1);
    v >>= CCI_PT_PAGE_OFFSET_BITS;

    idx = v & ((1LL << CCI_PT_VA_IDX_BITS) - 1);
    v >>= CCI_PT_VA_IDX_BITS;

    tag = v;
}

inline void
QA_SHIM_TLB_CLASS::AddrComponentsFromVA(
    const void *va,
    uint64_t& tag,
    uint64_t& idx,
    uint64_t& byteOffset)
{
    AddrComponentsFromVA(uint64_t(va), tag, idx, byteOffset);
}

inline void
QA_SHIM_TLB_CLASS::AddrComponentsFromPA(
    uint64_t pa,
    uint64_t& idx,
    uint64_t& byteOffset)
{
    uint64_t p = pa;

    byteOffset = p & ((1LL << CCI_PT_PAGE_OFFSET_BITS) - 1);
    p >>= CCI_PT_PAGE_OFFSET_BITS;

    idx = p & ((1LL << CCI_PT_PA_IDX_BITS) - 1);
    p >>= CCI_PT_PA_IDX_BITS;

    // PA_IDX_BITS must be large enough to represent all physical pages
    assert(p == 0);
}

inline uint64_t
QA_SHIM_TLB_CLASS::AddrToPTE(
    uint64_t va,
    uint64_t pa)
{
    assert((pa & ~((1LL << CCI_PT_PA_IDX_BITS) - 1)) == 0);

    return ((va << CCI_PT_PA_IDX_BITS) | pa);
}

inline uint64_t
QA_SHIM_TLB_CLASS::AddrToPTE(
    const void* va,
    uint64_t pa)
{
    return AddrToPTE(uint64_t(va), pa);
}

#endif
