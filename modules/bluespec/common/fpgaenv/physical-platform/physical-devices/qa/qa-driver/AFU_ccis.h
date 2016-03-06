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

//
// This module holds a class used to emulate features that became available
// after CCI-S.
//

#ifndef AFU_CCIS_H
#define AFU_CCIS_H

#include "awb/provides/qa_platform_libs.h"
#if (CCI_S_IFC != 0)

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
#include "cci_mpf_shim_vtp_params.h"


typedef class AFU_CCIS_CLASS* AFU_CCIS;
typedef class AFU_CLASS* AFU;


class AFU_CCIS_CLASS : public CAASBase
{
  public:
    AFU_CCIS_CLASS(AFU afu);
    ~AFU_CCIS_CLASS();

    //
    // Allocate a memory buffer shared by the host and an FPGA.
    //
    void* CreateSharedBufferInVM(size_t size_bytes);
    void FreeSharedBuffer(void* va);

    // Virtual to physical translation for allocated objects
    btPhysAddr SharedBufferVAtoPA(const void* va);

  private:
    void Initialize();

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

    // Number of tag bits for a VA.  Tags are the VA bits not covered by
    // the page offset and the hash table index.
    const uint32_t vaTagBits = CCI_PT_VA_BITS -
                               CCI_PT_VA_IDX_BITS -
                               CCI_PT_PAGE_OFFSET_BITS;

    // Size of a single PTE.  PTE is a tuple: VA tag and PA page index.
    // The size is rounded up to a multiple of bytes.
    const uint32_t pteBytes = (vaTagBits + CCI_PT_PA_IDX_BITS + 7) / 8;

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

    AFU            m_afu;
    btCSROffset    m_csr_base;          // Base address of VTP CSRs

    bool           did_init;
};


inline void
AFU_CCIS_CLASS::AddrComponentsFromVA(
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

    tag = v & ((1LL << vaTagBits) - 1);

    // Make sure no address bits were lost in the conversion.  The high bits
    // beyond CCI_PT_VA_BITS are sign extended.
    if (CCI_PT_VA_BITS != 64)
    {
        int64_t va_check = va;
        // Shift all but the high bit of the VA range to the right.  All the
        // resulting bits must match.
        va_check >>= (CCI_PT_VA_BITS - 1);
        assert((va_check == 0) || (va_check == -1));
    }
}


inline void
AFU_CCIS_CLASS::AddrComponentsFromVA(
    const void *va,
    uint64_t& tag,
    uint64_t& idx,
    uint64_t& byteOffset)
{
    AddrComponentsFromVA(uint64_t(va), tag, idx, byteOffset);
}

inline void
AFU_CCIS_CLASS::AddrComponentsFromPA(
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
AFU_CCIS_CLASS::AddrToPTE(
    uint64_t va,
    uint64_t pa)
{
    assert((pa & ~((1LL << CCI_PT_PA_IDX_BITS) - 1)) == 0);

    return ((va << CCI_PT_PA_IDX_BITS) | pa);
}

inline uint64_t
AFU_CCIS_CLASS::AddrToPTE(
    const void* va,
    uint64_t pa)
{
    return AddrToPTE(uint64_t(va), pa);
}

#endif // CCI_S_IFC
#endif // AFU_CCIS_H
