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

#include "test_random.h"
#include <time.h>
#include <boost/format.hpp>


// ========================================================================
//
// Each test must provide these functions used by main to find the
// specific test instance.
//
// ========================================================================


void testConfigOptions(po::options_description &desc)
{
    // Add test-specific options
    desc.add_options()
        ("enable-checker", po::value<bool>()->default_value(true), "Enable read value checker")
        ("enable-reads", po::value<bool>()->default_value(true), "Enable reads")
        ("enable-rw-conflicts", po::value<bool>()->default_value(true), "Enable address conflicts between reads and writes")
        ("enable-pw", po::value<bool>()->default_value(true), "Enable partial writes")
        ("enable-writes", po::value<bool>()->default_value(true), "Enable writes")
        ("enable-wro", po::value<bool>()->default_value(true), "Enable write/read hazard detection")
        ("repeat", po::value<int>()->default_value(1), "Number of repetitions")
        ("tc", po::value<int>()->default_value(0), "Test length (cycles)")
        ("ts", po::value<int>()->default_value(1), "Test length (seconds)")
        ;
}

CCI_TEST* allocTest(const po::variables_map& vm, AAL_SVC_WRAPPER& svc)
{
    return new TEST_RANDOM(vm, svc);
}


// ========================================================================
//
// Random traffic test.
//
// ========================================================================

btInt TEST_RANDOM::test()
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

    // What's the AFU frequency (MHz)?
    uint64_t afu_mhz = readCommonCSR(CSR_COMMON_FREQ);

    uint64_t cycles = uint64_t(vm["tc"].as<int>());
    if (cycles == 0)
    {
        // Didn't specify --tc.  Use seconds instead.
        cycles = uint64_t(vm["ts"].as<int>()) * afu_mhz * 1000 * 1000;
    }

    // Run length in seconds
    double run_sec = double(cycles) / (double(afu_mhz) * 1000.0 * 1000.0);

    const uint64_t counter_bits = 40;
    if (cycles & (int64_t(-1) << counter_bits))
    {
        cerr << "Run length overflows " << counter_bits << " bit counter" << endl;
        exit(1);
    }

    uint64_t enable_checker = (vm["enable-checker"].as<bool>() ? 1 : 0);
    uint64_t enable_reads = (vm["enable-reads"].as<bool>() ? 1 : 0);
    uint64_t enable_rw_conflicts = (vm["enable-rw-conflicts"].as<bool>() ? 1 : 0);
    uint64_t enable_pw = (vm["enable-pw"].as<bool>() ? 1 : 0);
    uint64_t enable_writes = (vm["enable-writes"].as<bool>() ? 1 : 0);
    uint64_t enable_wro = (vm["enable-wro"].as<bool>() ? 1 : 0);

    // Wait for the HW to be ready
    while (((readTestCSR(7) >> 4) & 1) == 0)
    {
        sleep(1);
    }

    uint64_t trips = uint64_t(vm["repeat"].as<int>());
    uint64_t iter = 0;
    while (trips--)
    {
        // Start the test
        writeTestCSR(0,
                     (cycles << 6) |
                     (enable_pw << 5) |
                     (enable_rw_conflicts << 4) |
                     (enable_checker << 3) |
                     (enable_wro << 2) |
                     (enable_writes << 1) |
                     enable_reads);

        // Wait for test to signal it is complete
        struct timespec ms;
        ms.tv_sec = 1;
        ms.tv_nsec = 1000000;

        while (*dsm == 0)
        {
            nanosleep(&ms, NULL);
        }

        totalCycles += cycles;

        uint64_t read_cnt = readTestCSR(4);
        uint64_t write_cnt = readTestCSR(5);
        uint64_t checked_read_cnt = readTestCSR(6);

        cout << "[" << ++iter << "] "
             << read_cnt << " reads ("
             << boost::format("%.1f") % ((double(read_cnt) * CL(1) / 0x40000000) / run_sec) << " GB/s), "
             << write_cnt << " writes ("
             << boost::format("%.1f") % ((double(write_cnt) * CL(1) / 0x40000000) / run_sec) << " GB/s) "
             << " [" << checked_read_cnt << " reads checked]"
             << endl;

        if (*dsm != 1)
        {
            // Error!
            dbgRegDump(readTestCSR(7));
            return (*dsm == 1) ? 1 : 2;
        }

        *dsm = 0;
    }

    return 0;
}


uint64_t
TEST_RANDOM::testNumCyclesExecuted()
{
    return totalCycles;
}


void
TEST_RANDOM::dbgRegDump(uint64_t r)
{
    cout << "Test random state:" << endl
         << "  State:           " << ((r >> 8) & 255) << endl
         << "  FIU C0 Alm Full: " << (r & 1) << endl
         << "  FIU C1 Alm Full: " << ((r >> 1) & 1) << endl
         << "  Error:           " << ((r >> 2) & 1) << endl
         << "  CHK FIFO Full:   " << ((r >> 3) & 1) << endl
         << "  CHK RAM Ready:   " << ((r >> 4) & 1) << endl;
}
