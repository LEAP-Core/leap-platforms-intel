// Copyright(c) 2007-2016, Intel Corporation
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

#ifndef __TEST_MEM_PERF_H__
#define __TEST_MEM_PERF_H__ 1

#include "cci_test.h"

class TEST_MEM_PERF : public CCI_TEST
{
  private:
    enum
    {
        TEST_CSR_BASE = 32
    };

    typedef struct
    {
        uint64_t read_cnt;
        uint64_t write_cnt;
        uint64_t vl0_cnt;
        uint64_t vh0_cnt;
        uint64_t vh1_cnt;
    }
    t_test_stats;

  public:
    TEST_MEM_PERF(const po::variables_map& vm, AAL_SVC_WRAPPER& svc) :
        CCI_TEST(vm, svc),
        totalCycles(0)
    {};

    ~TEST_MEM_PERF() {};

    // Returns 0 on success
    btInt test();

    uint64_t testNumCyclesExecuted();

  private:
    int runTest(uint64_t cycles,
                uint64_t stride,
                uint64_t vc,
                uint64_t mcl,
                uint64_t wrline_m,
                uint64_t rdline_s,
                uint64_t enable_writes,
                uint64_t enable_reads,
                t_test_stats* stats);

    void dbgRegDump(uint64_t r);

    volatile uint64_t* dsm;
    uint64_t totalCycles;
};

#endif // _TEST_MEM_PERF_H_
