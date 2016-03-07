// Copyright(c) 2015-2016, Intel Corporation
//
// Redistribution  and  use  in source  and  binary  forms,  with  or  without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of  source code  must retain the  above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name  of Intel Corporation  nor the names of its contributors
//   may be used to  endorse or promote  products derived  from this  software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
// IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
// LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
// CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
// SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
// INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
// CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

//****************************************************************************
/// @file cci_mpf_shim_vtp_pt.cpp
/// @brief Page table creation for MPF VTP service.
/// @ingroup VTPService
/// @verbatim
///
/// Construct a page table for translating virtual addresses shared between
/// FPGA and host process to physical addresses.
///
/// Note: this is not an AAL service, but a component of the MPF service (which
/// is).
///
/// AUTHOR: Michael Adler, Intel Corporation
///
/// HISTORY:
/// WHEN:          WHO:     WHAT:
/// 03/05/2016     MA       Initial version
/// @endverbatim
//****************************************************************************

#include <assert.h>

#include "cci_mpf_shim_vtp_pt.h"


BEGIN_NAMESPACE(AAL)


/////////////////////////////////////////////////////////////////////////////
//////                                                                ///////
//////                                                                ///////
/////                    VTP Page Table Management                     //////
//////                                                                ///////
//////                                                                ///////
/////////////////////////////////////////////////////////////////////////////


/// @addtogroup VTPService
/// @{

//-----------------------------------------------------------------------------
// Public functions
//-----------------------------------------------------------------------------

MPFVTP_PAGE_TABLE::MPFVTP_PAGE_TABLE()
{
}


bool
MPFVTP_PAGE_TABLE::ptInitialize()
{
    // Allocate the page table.  The size of the page table is a function
    // of the PTE index space.
    size_t pt_size = (1LL << CCI_PT_LINE_IDX_BITS) * CL(1);
    m_pPageTable = ptAllocSharedPage(pt_size, &m_pPageTablePA);
    assert(m_pPageTable != NULL);

    // clear table
    memset(m_pPageTable, 0, pt_size);

    m_pPageTableEnd = m_pPageTable + pt_size;

    // The page table is hashed.  It begins with lines devoted to the hash
    // table.  The remainder of the buffer is available for overflow lines.
    // Initialize the free pointer of overflow lines, which begins at the
    // end of the hash table.
    m_pPageTableFree = m_pPageTable + (1LL << CCI_PT_VA_IDX_BITS) * CL(1);
    assert(m_pPageTableFree <= m_pPageTableEnd);

    return true;
}


btPhysAddr
MPFVTP_PAGE_TABLE::ptGetPageTableRootPA() const
{
    return m_pPageTablePA;
}


bool
MPFVTP_PAGE_TABLE::ptInsertPageMapping(
    btVirtAddr va,
    btPhysAddr pa,
    MPFVTP_PAGE_SIZE size)
{
    //
    // VA components are the offset within the 2MB-aligned page, the index
    // within the direct-mapped page table hash vector and the remaining high
    // address bits: the tag.
    //
    uint64_t va_tag;
    uint64_t va_idx;
    uint64_t va_offset;
    AddrComponentsFromVA(va, va_tag, va_idx, va_offset);
    ASSERT(va_offset == 0);

    //
    // PA components are the offset within the 2MB-aligned page and the
    // index of the 2MB aligned physical page (low bits dropped).
    //
    uint64_t pa_idx;
    uint64_t pa_offset;
    AddrComponentsFromPA(pa, pa_idx, pa_offset);
    ASSERT(pa_offset == 0);

    //
    // The page table is hashed by the VA index.  Compute the address of
    // the line given the hash.
    //
    uint8_t* p = m_pPageTable + va_idx * CL(1);

    //
    // Find a free entry.
    //
    uint32_t n = 0;
    while (true)
    {
        if (n++ != ptesPerLine)
        {
            // Walking PTEs in a line
            uint64_t tmp_va_tag;
            uint64_t tmp_pa_idx;
            ReadPTE(p, tmp_va_tag, tmp_pa_idx);

            if (tmp_va_tag == 0)
            {
                // Found a free entry
                break;
            }

            // Entry was busy.  Move on to the next one.
            p += pteBytes;
        }
        else
        {
            // End of the line.  Is there an overflow line already?
            n = 0;

            uint64_t next_idx = ReadTableIdx(p);
            if (next_idx != 0)
            {
                // Overflow allocated.  Switch to it and keep searching.
                p = m_pPageTable + next_idx * CL(1);
            }
            else
            {
                // Need a new overflow line.  Is there space in the page table?
                ASSERT(m_pPageTableFree < m_pPageTableEnd);

                // Add a next line pointer to the current entry.
                WriteTableIdx(p, (m_pPageTableFree - m_pPageTable) / CL(1));
                p = m_pPageTableFree;
                m_pPageTableFree += CL(1);

                // Write the new PTE at p.
                break;
            }
        }
    }

    // Add the new PTE
    WritePTE(p, va_tag, pa_idx);

    return true;
}


bool
MPFVTP_PAGE_TABLE::ptTranslateVAtoPA(btVirtAddr va,
                                   btPhysAddr *pa)
{
    *pa = 0;

    // Get the hash index and VA tag
    uint64_t tag;
    uint64_t idx;
    uint64_t offset;
    AddrComponentsFromVA(va, tag, idx, offset);

    // The idx field is the hash bucket in which the VA will be found.
    uint8_t* pte = m_pPageTable + idx * CL(1);

    // Search for a matching tag in the hash bucket.  The bucket is a set
    // of vectors PTEs chained in a linked list.
    while (true)
    {
        // Walk through one vector in one line
        for (int n = 0; n < ptesPerLine; n += 1)
        {
            uint64_t va_tag;
            uint64_t pa_idx;
            ReadPTE(pte, va_tag, pa_idx);

            if (va_tag == tag)
            {
                // Found it!
                *pa = (pa_idx << CCI_PT_PAGE_OFFSET_BITS) | offset;
                return true;
            }

            // End of the PTE list?
            if (va_tag == 0)
            {
                // Failed to find an entry for VA
                return false;
            }

            pte += pteBytes;
        }

        // VA not found in current line.  Does this line of PTEs link to
        // another?
        pte = m_pPageTable + ReadTableIdx(pte) * CL(1);

        // End of list?  (Table index was NULL.)
        if (pte == m_pPageTable)
        {
            return false;
        }
    }
}



//-----------------------------------------------------------------------------
// Private functions
//-----------------------------------------------------------------------------

void
MPFVTP_PAGE_TABLE::ReadPTE(
    const uint8_t* pte,
    uint64_t& vaTag,
    uint64_t& paIdx)
{
    // Might not be a natural size so use memcpy
    uint64_t e = 0;
    memcpy(&e, pte, pteBytes);

    paIdx = e & ((1LL << CCI_PT_PA_IDX_BITS) - 1);

    vaTag = e >> CCI_PT_PA_IDX_BITS;
    vaTag &= (1LL << vaTagBits) - 1;

    // VA is sign extended from its size to 64 bits
    if (CCI_PT_VA_BITS != 64)
    {
        vaTag <<= (64 - vaTagBits);
        vaTag = uint64_t(int64_t(vaTag) >> (64 - vaTagBits));
    }
}


uint64_t
MPFVTP_PAGE_TABLE::ReadTableIdx(const uint8_t* p)
{
    // Might not be a natural size
    uint64_t e = 0;
    memcpy(&e, p, (CCI_PT_LINE_IDX_BITS + 7) / 8);

    return e & ((1LL << CCI_PT_LINE_IDX_BITS) - 1);
}


void
MPFVTP_PAGE_TABLE::WritePTE(uint8_t* pte, uint64_t vaTag, uint64_t paIdx)
{
    uint64_t p = AddrToPTE(vaTag, paIdx);

    // Might not be a natural size so use memcpy
    memcpy(pte, &p, pteBytes);
}


void
MPFVTP_PAGE_TABLE::WriteTableIdx(uint8_t* p, uint64_t idx)
{
    // Might not be a natural size
    memcpy(p, &idx, (CCI_PT_LINE_IDX_BITS + 7) / 8);
}


void
MPFVTP_PAGE_TABLE::ptDumpPageTable()
{
    // Loop through all lines in the hash table
    for (int hash_idx = 0; hash_idx < (1LL << CCI_PT_VA_IDX_BITS); hash_idx += 1)
    {
        int cur_idx = hash_idx;
        uint8_t* pte = m_pPageTable + hash_idx * CL(1);

        // Loop over all lines in the hash group
        while (true)
        {
            int n;
            // Loop over all PTEs in a single line
            for (n = 0; n < ptesPerLine; n += 1)
            {
                uint64_t va_tag;
                uint64_t pa_idx;
                ReadPTE(pte, va_tag, pa_idx);

                // End of the PTE list within the current hash group?
                if (va_tag == 0) break;

                //
                // The VA in a PTE is the combination of the tag (stored
                // in the PTE) and the hash table index.  The table index
                // is mapped directly from the low bits of the VA's line
                // address.
                //
                // The PA in a PTE is stored as the index of the 2MB-aligned
                // physical address.
                pte += pteBytes;
            }

            // If the PTE list within the current hash group is incomplete then
            // we have walked all PTEs in the line.
            if (n != ptesPerLine) break;

            // Follow the next pointer to the connected line holding another
            // vector of PTEs.
            cur_idx = ReadTableIdx(pte);
            pte = m_pPageTable + cur_idx * CL(1);
            // End of list?  (Table index was NULL.)
            if (pte == m_pPageTable) break;
        }
    }
}

inline void
MPFVTP_PAGE_TABLE::AddrComponentsFromVA(
    uint64_t va,
    uint64_t& tag,
    uint64_t& idx,
    uint64_t& byteOffset )
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
        ASSERT((va_check == 0) || (va_check == -1));
    }
}


inline void
MPFVTP_PAGE_TABLE::AddrComponentsFromVA(
    const void *va,
    uint64_t& tag,
    uint64_t& idx,
    uint64_t& byteOffset)
{
    AddrComponentsFromVA(uint64_t(va), tag, idx, byteOffset);
}

inline void
MPFVTP_PAGE_TABLE::AddrComponentsFromPA(
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
    ASSERT(p == 0);
}


inline uint64_t
MPFVTP_PAGE_TABLE::AddrToPTE(uint64_t va, uint64_t pa)
{
    ASSERT((pa & ~((1LL << CCI_PT_PA_IDX_BITS) - 1)) == 0);

    return ((va << CCI_PT_PA_IDX_BITS) | pa);
}


inline uint64_t
MPFVTP_PAGE_TABLE::AddrToPTE(const void* va, uint64_t pa)
{
    return AddrToPTE(uint64_t(va), pa);
}

/// @} group VTPService

END_NAMESPACE(AAL)
