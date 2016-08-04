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

#include "base/cci_test.h"

void dbgRegDump(uint64_t r)
{
    cout << "Test random state:" << endl
         << "  State:           " << ((r >> 8) & 255) << endl
         << "  FIU C0 Alm Full: " << (r & 1) << endl
         << "  FIU C1 Alm Full: " << ((r >> 1) & 1) << endl
         << "  Error:           " << ((r >> 2) & 1) << endl
         << "  CHK FIFO Full:   " << ((r >> 3) & 1) << endl
         << "  CHK RAM Ready:   " << ((r >> 4) & 1) << endl;
}


btInt CCI_TEST::test()
{
    // Allocate memory for control
    volatile uint64_t* dsm = (uint64_t*) this->malloc(4096);
    memset((void*)dsm, 0, 4096);

    // Allocate memory for read/write tests.  The HW indicates the size
    // of the memory buffer in CSR 0.
    uint64_t addr_info = readTestCSR(0);
    
    // Low 16 bits holds the number of line address bits required
    uint64_t n_bytes = CL(1) * (1LL << uint16_t(addr_info));

    cout << "Allocating " << n_bytes / (1024 * 1024) << "MB test buffer..." << endl;
    volatile uint64_t* mem = (uint64_t*) this->malloc(n_bytes);
    memset((void*)mem, 0, n_bytes);

    //
    // Configure the HW test
    //
    writeTestCSR(1, uint64_t(dsm) / CL(1));
    writeTestCSR(2, uint64_t(mem) / CL(1));
    writeTestCSR(3, (n_bytes / CL(1)) - 1);

    uint64_t cycles = uint64_t(vm["tc"].as<int>());
    if (cycles == 0)
    {
        // Didn't specify --tc.  Use seconds instead.

        // What's the AFU frequency (MHz)?
        uint64_t afu_mhz = readCommonCSR(CSR_COMMON_FREQ);
        cycles = uint64_t(vm["ts"].as<int>()) * afu_mhz * 1000 * 1000;
    }

    uint64_t trips = uint64_t(vm["repeat"].as<int>());
    uint64_t iter = 0;
    while (trips--)
    {
        // Start the test
        writeTestCSR(0, cycles);

        // Wait for test to signal it is complete
        while (*dsm == 0) ;

        cout << "[" << ++iter << "] Checked " << readTestCSR(4) << " reads" << endl;

        if (*dsm != 1)
        {
            // Error!
            dbgRegDump(readTestCSR(5));
            return (*dsm == 1) ? 1 : 2;
        }

        *dsm = 0;
    }

    return 0;
}

void CCI_TEST::testConfigOptions(po::options_description &desc)
{
    // Add test-specific options
    desc.add_options()
        ("tc", po::value<int>()->default_value(0), "Test length (cycles)")
        ("ts", po::value<int>()->default_value(1), "Test length (seconds)")
        ("repeat", po::value<int>()->default_value(1), "Number of repetitions")
        ;
}
