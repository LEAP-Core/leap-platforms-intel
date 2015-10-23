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

#include <iostream>
#include <string>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <assert.h>

#include "awb/provides/qa_driver.h"
#include "awb/provides/qa_driver_shims.h"


QA_SHIM_TLB_CLASS::QA_SHIM_TLB_CLASS(AFU_CLIENT afuClient) :
    m_afuClient(afuClient)
{
    // The three VA fields must fill a 64 bit virtual address
    assert(CCI_PT_VA_TAG_BITS + CCI_PT_VA_IDX_BITS + CCI_PT_PAGE_OFFSET_BITS == 64);

    // There must be overflow space in the page table
    assert(CCI_PT_VA_IDX_BITS < CCI_PT_LINE_IDX_BITS);

    // Allocate the page table.  The size of the page table is a function
    // of the PTE index space.
    size_t pt_size = (1LL << CCI_PT_LINE_IDX_BITS) * CL(1);

    // Allocate the table.  The allocator fills it with zeros.
    AFU_BUFFER pt = afuClient->CreateSharedBuffer(pt_size);
    assert(pt && (pt->numBytes == pt_size));

    m_pageTable = (uint8_t*)pt->virtualAddress;
    m_pageTablePA = pt->physicalAddress;

    m_pageTableEnd = m_pageTable + pt_size;

    // The page table is hashed.  It begins with lines devoted to the hash
    // table.  The remainder of the buffer is available for overflow lines.
    // Initialize the free pointer of overflow lines, which begins at the
    // end of the hash table.
    m_pageTableFree = m_pageTable + (1LL << CCI_PT_VA_IDX_BITS) * CL(1);
    assert(m_pageTableFree <= m_pageTableEnd);

    // Tell the hardware the address of the table
    afuClient->WriteCSR64(CSR_AFU_PAGE_TABLE_BASE, m_pageTablePA);
}


QA_SHIM_TLB_CLASS::~QA_SHIM_TLB_CLASS()
{
}


void*
QA_SHIM_TLB_CLASS::CreateSharedBufferInVM(size_t size_bytes)
{
    AutoLock(this);

    // Align request to page size
    size_bytes = (size_bytes + pageSize - 1) & pageMask;

    // * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *
    //
    //  This method of allocating a large virtual workspace is temporary.
    //  When AAL is capable of doing it internally this hack will be
    //  replaced with a simple allocation call.
    // 
    // * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * *


    // Map a region of the requested size.  This will reserve a virtual
    // memory address space.  As pages are allocated they will be
    // mapped into this space.
    //
    // An extra page is added to the request in order to enable alignment
    // of the base address.  Linux is only guaranteed to return 4 KB aligned
    // addresses and we want large page aligned virtual addresses.
    void* va_base;
    size_t va_base_len = size_bytes + pageSize;
    va_base = mmap(NULL, va_base_len,
                   PROT_READ | PROT_WRITE,
                   MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    assert(va_base != MAP_FAILED);
    printf("va_base %p\n", va_base);

    void* va_aligned = (void*)((size_t(va_base) + pageSize - 1) & pageMask);
    printf("va_aligned %p\n", va_aligned);

    // Trim off the unnecessary extra space after alignment
    size_t trim = pageSize - (size_t(va_aligned) - size_t(va_base));
    printf("va_base_len trimmed by 0x%llx to 0x%llx\n", trim, va_base_len - trim);
    assert(mremap(va_base, va_base_len, va_base_len - trim, 0) == va_base);
    va_base_len -= trim;

    // How many page size buffers are needed to satisfy the request?
    size_t n_buffers = size_bytes / pageSize;

    // Buffer mapping will begin at the end of the va_aligned region
    void* va_alloc = (void*)(size_t(va_aligned) + pageSize * (n_buffers - 1));

    // Allocate the buffers
    for (size_t i = 0; i < n_buffers; i++)
    {
        // Get a page size buffer
        AFU_BUFFER buffer = m_afuClient->CreateSharedBuffer(pageSize);
        assert(buffer != NULL);

        // Shrink the reserved area in order to make a hole in the virtual
        // address space.
        if (va_base_len == pageSize)
        {
            munmap(va_base, va_base_len);
            va_base_len = 0;
        }
        else
        {
            assert(mremap(va_base, va_base_len, va_base_len - pageSize, 0) == va_base);
            va_base_len -= pageSize;
        }

        // Move the shared buffer's VA to the proper slot
        if (buffer->virtualAddress != va_alloc)
        {
            printf("remap %p to %p\n", (void*)buffer->virtualAddress, va_alloc);
            assert(mremap((void*)buffer->virtualAddress, pageSize, pageSize,
                          MREMAP_MAYMOVE | MREMAP_FIXED,
                          va_alloc) == va_alloc);
        }

        // Add the mapping to the page table
        InsertPageMapping(va_alloc, buffer->physicalAddress);

        // Next VA
        va_alloc = (void*)(size_t(va_alloc) - pageSize);

        // AAL gets confused if the same VA reappears.  Lock the VA returned
        // by AAL even though it isn't needed any more.
        mmap((void*)buffer->virtualAddress, getpagesize(), PROT_READ,
             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, 0, 0);

        assert((buffer->physicalAddress & ~pageMask) == 0);
        delete buffer;
    }

    if (va_base_len != 0)
    {
        munmap(va_base, va_base_len);
    }

    DumpPageTable();

    return va_aligned;
}


void
QA_SHIM_TLB_CLASS::FreeSharedBuffer(void* va)
{
    // Because of the remapping we can't currently free workspaces.
    // AAL doesn't know about the reorganized virtual address space and
    // won't find the pages to free.  Pages are cleaned up when the
    // device is closed.
}


void
QA_SHIM_TLB_CLASS::InsertPageMapping(const void* va, btPhysAddr pa)
{
    printf("Map %p at 0x%08lx\n", va, pa);

    //
    // VA components are the offset within the 2MB-aligned page, the index
    // within the direct-mapped page table hash vector and the remaining high
    // address bits: the tag.
    //
    uint64_t va_tag;
    uint64_t va_idx;
    uint64_t va_offset;
    AddrComponentsFromVA(va, va_tag, va_idx, va_offset);
    assert(va_offset == 0);

    //
    // PA components are the offset within the 2MB-aligned page and the
    // index of the 2MB aligned physical page (low bits dropped).
    //
    uint64_t pa_idx;
    uint64_t pa_offset;
    AddrComponentsFromPA(pa, pa_idx, pa_offset);
    assert(pa_offset == 0);

    //
    // The page table is hashed by the VA index.  Compute the address of
    // the line given the hash.
    //
    uint8_t* p = m_pageTable + va_idx * CL(1);

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
                p = m_pageTable + next_idx * CL(1);
            }
            else
            {
                // Need a new overflow line.  Is there space in the page table?
                assert(m_pageTableFree < m_pageTableEnd);

                // Add a next line pointer to the current entry.
                WriteTableIdx(p, (m_pageTableFree - m_pageTable) / CL(1));
                p = m_pageTableFree;
                m_pageTableFree += CL(1);

                // Write the new PTE at p.
                break;
            }
        }
    }

    // Add the new PTE
    WritePTE(p, va_tag, pa_idx);
}


void
QA_SHIM_TLB_CLASS::ReadPTE(
    const uint8_t* pte,
    uint64_t& vaTag,
    uint64_t& paIdx)
{
    // Might not be a natural size so use memcpy
    uint64_t e = 0;
    memcpy(&e, pte, pteBytes);

    paIdx = e & ((1LL << CCI_PT_PA_IDX_BITS) - 1);

    vaTag = e >> CCI_PT_PA_IDX_BITS;
    vaTag &= (1LL << CCI_PT_VA_TAG_BITS) - 1;
}

uint64_t
QA_SHIM_TLB_CLASS::ReadTableIdx(
    const uint8_t* p)
{
    // Might not be a natural size
    uint64_t e = 0;
    memcpy(&e, p, (CCI_PT_LINE_IDX_BITS + 7) / 8);

    return e & ((1LL << CCI_PT_LINE_IDX_BITS) - 1);
}


void
QA_SHIM_TLB_CLASS::WritePTE(
    uint8_t* pte,
    uint64_t vaTag,
    uint64_t paIdx)
{
    uint64_t p = AddrToPTE(vaTag, paIdx);

    // Might not be a natural size so use memcpy
    memcpy(pte, &p, pteBytes);
}


void
QA_SHIM_TLB_CLASS::WriteTableIdx(
    uint8_t* p,
    uint64_t idx)
{
    // Might not be a natural size
    memcpy(p, &idx, (CCI_PT_LINE_IDX_BITS + 7) / 8);
}


//
// Translate VA to PA using page table.
//
btPhysAddr
QA_SHIM_TLB_CLASS::SharedBufferVAtoPA(const void* va)
{
    // Get the hash index and VA tag
    uint64_t tag;
    uint64_t idx;
    uint64_t offset;
    AddrComponentsFromVA(va, tag, idx, offset);

    // The idx field is the hash bucket in which the VA will be found.
    uint8_t* pte = m_pageTable + idx * CL(1);

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
                return (pa_idx << CCI_PT_PAGE_OFFSET_BITS) | offset;
            }

            // End of the PTE list?
            if (va_tag == 0)
            {
                // Failed to find an entry for VA
                return 0;
            }

            pte += pteBytes;
        }

        // VA not found in current line.  Does this line of PTEs link to
        // another?
        pte = m_pageTable + ReadTableIdx(pte) * CL(1);

        // End of list?  (Table index was NULL.)
        if (pte == m_pageTable)
        {
            return 0;
        }
    }
}


void
QA_SHIM_TLB_CLASS::DumpPageTable()
{
    printf("Page table dump:\n");
    printf("  %lld lines, %ld PTEs per line, max. memory represented in PTE %lld GB\n",
           1LL << CCI_PT_LINE_IDX_BITS,
           ptesPerLine,
           ((1LL << CCI_PT_LINE_IDX_BITS) * ptesPerLine * 2) / 1024);

    // Loop through all lines in the hash table
    for (int hash_idx = 0; hash_idx < (1LL << CCI_PT_VA_IDX_BITS); hash_idx += 1)
    {
        uint8_t* pte = m_pageTable + hash_idx * CL(1);

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
                printf("    VA 0x%016llx -> PA 0x%016llx\n",
                       (va_tag << (CCI_PT_VA_IDX_BITS + CCI_PT_PAGE_OFFSET_BITS)) |
                       (hash_idx << CCI_PT_PAGE_OFFSET_BITS),
                       pa_idx << CCI_PT_PAGE_OFFSET_BITS);

                pte += pteBytes;
            }

            // If the PTE list within the current hash group is incomplete then
            // we have walked all PTEs in the line.
            if (n != ptesPerLine) break;

            // Follow the next pointer to the connected line holding another
            // vector of PTEs.
            pte = m_pageTable + ReadTableIdx(pte) * CL(1);
            // End of list?  (Table index was NULL.)
            if (pte == m_pageTable) break;
        }
    }
}
