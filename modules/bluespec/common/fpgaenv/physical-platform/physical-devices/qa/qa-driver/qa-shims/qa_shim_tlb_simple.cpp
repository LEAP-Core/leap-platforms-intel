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
    m_vtop = NULL;
    m_va = NULL;
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

    if (m_vtop != NULL) delete[] m_vtop;
    m_vtop = new btPhysAddr[n_buffers];
    m_va = va_aligned;

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

        // Next VA
        va_alloc = (void*)(size_t(va_alloc) - pageSize);

        // AAL gets confused if the same VA reappears.  Lock the VA returned
        // by AAL even though it isn't needed any more.
        mmap((void*)buffer->virtualAddress, getpagesize(), PROT_READ,
             MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, 0, 0);

        assert((buffer->physicalAddress & ~pageMask) == 0);
        m_vtop[n_buffers - i - 1] = buffer->physicalAddress;
        delete buffer;
    }

    if (va_base_len != 0)
    {
        munmap(va_base, va_base_len);
    }

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


btPhysAddr
QA_SHIM_TLB_CLASS::SharedBufferVAtoPA(const void* va)
{
    uint64_t page_offset = uint64_t(va) & ~pageMask;
    return m_vtop[((uint64_t(va) & pageMask) -  uint64_t(m_va)) / pageSize] | page_offset;
}
