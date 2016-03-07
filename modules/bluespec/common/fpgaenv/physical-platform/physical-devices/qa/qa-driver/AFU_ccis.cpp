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

// Only used on CCI-S
#if (CCI_S_IFC != 0)

#include "awb/provides/qa_cci_mpf_hw_shims.h"
#include "awb/provides/qa_cci_hw_if.h"
#include "awb/provides/qa_cci_mpf_hw.h"


AFU_CCIS_CLASS::AFU_CCIS_CLASS(AFU afu) :
    m_afu(afu),
    m_csr_base(0),
    did_init(false)
{
    ptInitialize();
}


void
AFU_CCIS_CLASS::Initialize()
{
    did_init = true;

    //
    // Find the VTP feature header in the AFU.
    //
    btCSROffset f_addr = 0;
    // Get the main AFU feature header
    CCIP_FEATURE_DFH f_afu(m_afu->ReadCSR64(f_addr));

    // Walk the list of features, looking for VTP
    bool is_eol = f_afu.isEOL();
    f_addr += f_afu.getNext();
    while (! is_eol)
    {
        CCIP_FEATURE_DFH f(m_afu->ReadCSR64(f_addr));
        printf("DFH 0x%04llx: %d 0x%016llx 0x%016llx\n", f_addr,
               f.getFeatureType(),
               m_afu->ReadCSR64(f_addr + 16),
               m_afu->ReadCSR64(f_addr + 8));
        if ((f.getFeatureType() == eFTYP_BBB) &&
            (m_afu->ReadCSR64(f_addr + 16) == 0xc8a2982fff9642bf) &&
            (m_afu->ReadCSR64(f_addr + 8)  == 0xa70545727f501901))
        {
            // Found VTP
            m_csr_base = f_addr;
            break;
        }

        f_addr += f.getNext();

        // EOL?
        is_eol = f.isEOL();
    }

    // Was the VTP CSR region found?
    assert(m_csr_base != 0);

    // Tell the hardware the address of the table
    m_afu->WriteCSR64(m_csr_base + CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR,
                      ptGetPageTableRootPA() / CL(1));
}


AFU_CCIS_CLASS::~AFU_CCIS_CLASS()
{
}


void*
AFU_CCIS_CLASS::CreateSharedBufferInVM(size_t size_bytes)
{
    if (! did_init) Initialize();

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
        AFU_BUFFER buffer = m_afu->CreateSharedBuffer(pageSize);
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
        ptInsertPageMapping(btVirtAddr(va_alloc),
                            buffer->physicalAddress,
                            MPFVTP_PAGE_2MB);

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

    ptDumpPageTable();

    return va_aligned;
}


void
AFU_CCIS_CLASS::FreeSharedBuffer(void* va)
{
    // Because of the remapping we can't currently free workspaces.
    // AAL doesn't know about the reorganized virtual address space and
    // won't find the pages to free.  Pages are cleaned up when the
    // device is closed.
}


//
// Translate VA to PA using page table.
//
btPhysAddr
AFU_CCIS_CLASS::SharedBufferVAtoPA(const void* va)
{
    if (! did_init) Initialize();

    btPhysAddr pa;
    assert(ptTranslateVAtoPA(btVirtAddr(va), &pa));
    return pa;
}


btVirtAddr
AFU_CCIS_CLASS::ptAllocSharedPage(btWSSize length, btPhysAddr* pa)
{
    AFU_BUFFER page = m_afu->CreateSharedBuffer(length);
    assert(page && (page->numBytes == length));

    *pa = page->physicalAddress;
    return btVirtAddr(page->virtualAddress);
}


#endif // CCI_S_IFC
