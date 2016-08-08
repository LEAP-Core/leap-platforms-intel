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

#ifndef __CCI_TEST_H__
#define __CCI_TEST_H__ 1

#include <string>
#include <boost/program_options.hpp>
namespace po = boost::program_options;

#include "aal_svc_wrapper.h"

//
// Interface to a standard test.
//

class CCI_TEST
{
  protected:
    enum
    {
        TEST_CSR_BASE = 32
    };

  public:
    CCI_TEST(const po::variables_map& vm, AAL_SVC_WRAPPER& svc) :
        vm(vm),
        svc(svc)
    {};

    ~CCI_TEST() {};

    // Returns 0 on success
    virtual btInt test() = 0;

    // Number of cycles executed in test.  Optional virtual method.  The
    // base class returns 0.
    virtual uint64_t testNumCyclesExecuted()
    {
        return 0;
    }

    //
    // Wrappers for commonly used requests
    //

    btVirtAddr malloc(btWSSize nBytes)
    {
        btVirtAddr va;
        assert(svc.m_pVTPService->bufferAllocate(nBytes, &va) == ali_errnumOK);
        return va;
    }

    void writeTestCSR(uint32_t idx, uint64_t v)
    {
        svc.m_pALIMMIOService->mmioWrite64(8 * (TEST_CSR_BASE + idx), v);
    }

    uint64_t readTestCSR(uint32_t idx)
    {
        btUnsigned64bitInt v;
        svc.m_pALIMMIOService->mmioRead64(8 * (TEST_CSR_BASE + idx), &v);

        return v;
    }

    //
    // CSRs available on all tests
    //
    typedef enum 
    {
        CSR_COMMON_DFH = 0,
        CSR_COMMON_ID_L = 1,
        CSR_COMMON_ID_H = 2,
        CSR_COMMON_FREQ = 8,
        CSR_COMMON_CACHE_RD_HITS = 9,
        CSR_COMMON_CACHE_RD_MISSES = 10,
        CSR_COMMON_CACHE_WR_HITS = 11,
        CSR_COMMON_CACHE_WR_MISSES = 12,
        CSR_COMMON_VL0_RESPS = 13
    }
    t_csr_common;

    uint64_t readCommonCSR(t_csr_common idx)
    {
        btUnsigned64bitInt v;
        svc.m_pALIMMIOService->mmioRead64(8 * uint32_t(idx), &v);

        return v;
    }


  protected:
    const po::variables_map& vm;
    AAL_SVC_WRAPPER& svc;
};


//
// A test module must provide the following functions:
//

// Set command line option definitions for test.  This is outside the
// CCI_TEST class because it is needed to configure the base AAL service
// before the test constructor is called.
void testConfigOptions(po::options_description &desc);

// Instantiate an instance of the specific test class
CCI_TEST* allocTest(const po::variables_map& vm, AAL_SVC_WRAPPER& svc);

#endif // __CCI_TEST_H__
