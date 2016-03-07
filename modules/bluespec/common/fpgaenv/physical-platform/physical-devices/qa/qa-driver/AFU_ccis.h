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

typedef class AFU_CCIS_CLASS* AFU_CCIS;
typedef class AFU_CLASS* AFU;


class AFU_CCIS_CLASS : public CAASBase, private MPFVTP_PAGE_TABLE
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
    // Page allocator used by MPFVTP_PAGE_TABLE to add pages to the
    // shared page table data structure.
    btVirtAddr ptAllocSharedPage(btWSSize length, btPhysAddr* pa);

    void Initialize();

    AFU            m_afu;
    btCSROffset    m_csr_base;          // Base address of VTP CSRs

    bool           did_init;

    const size_t pageSize = MB(2);
    const size_t pageMask = ~(pageSize - 1);
};

#endif // CCI_S_IFC
#endif // AFU_CCIS_H
