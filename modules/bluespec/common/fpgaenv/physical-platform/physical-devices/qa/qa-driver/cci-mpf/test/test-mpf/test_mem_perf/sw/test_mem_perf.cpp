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

#include "test_mem_perf.h"
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
        ("vc", po::value<int>()->default_value(0), "Channel (0=VA, 1=VL0, 2=VH0, 3=VH1)")
        ("rdline-s", po::value<bool>()->default_value(true), "Emit read requests with shared cache hint")
        ("wrline-m", po::value<bool>()->default_value(true), "Emit write requests with modified cache hint")
        ("mcl", po::value<int>()->default_value(1), "Multi-line requests (0 for random sizes)")
        ("max-stride", po::value<int>()->default_value(128), "Maximum stride value")
        ("tc", po::value<int>()->default_value(0), "Test length (cycles)")
        ("ts", po::value<int>()->default_value(1), "Test length (seconds)")
        ("test-mode", po::value<bool>()->default_value(false), "Generate simple memory patterns for testing address logic")
        ;
}

CCI_TEST* allocTest(const po::variables_map& vm, AAL_SVC_WRAPPER& svc)
{
    return new TEST_MEM_PERF(vm, svc);
}


// ========================================================================
//
//  Memory performance test.
//
// ========================================================================

btInt TEST_MEM_PERF::test()
{
    // Allocate memory for control
    dsm = (uint64_t*) this->malloc(4096);
    memset((void*)dsm, 0, 4096);

    // Allocate memory for read/write tests.  The HW indicates the size
    // of the memory buffer in CSR 0.
    uint64_t addr_info = readTestCSR(0);
    
    // Low 16 bits holds the number of line address bits required
    uint64_t n_bytes = CL(1) * (1LL << uint16_t(addr_info));

    cout << "# Allocating " << n_bytes / (1024 * 1024) << "MB read test buffer..." << endl;
    volatile uint64_t* rd_mem = (uint64_t*) this->malloc(n_bytes);
    memset((void*)rd_mem, 0, n_bytes);

    cout << "# Allocating " << n_bytes / (1024 * 1024) << "MB write test buffer..." << endl;
    volatile uint64_t* wr_mem = (uint64_t*) this->malloc(n_bytes);
    memset((void*)wr_mem, 0, n_bytes);

    //
    // Configure the HW test
    //
    writeTestCSR(1, uint64_t(dsm) / CL(1));
    writeTestCSR(2, uint64_t(rd_mem) / CL(1));
    writeTestCSR(3, uint64_t(wr_mem) / CL(1));
    writeTestCSR(4, (n_bytes / CL(1)) - 1);

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

    uint64_t vc = uint64_t(vm["vc"].as<int>());
    assert(vc < 4);

    uint64_t rdline_s = (vm["rdline-s"].as<bool>() ? 1 : 0);
    uint64_t wrline_m = (vm["wrline-m"].as<bool>() ? 1 : 0);

    uint64_t mcl = uint64_t(vm["mcl"].as<int>());
    if ((mcl > 4) || (mcl == 3))
    {
        cerr << "Illegal multi-line (mcl) parameter:  " << mcl << endl;
        exit(1);
    }
    // Encode mcl as 3 bits.  The low 2 are the Verilog t_ccip_clLen and the
    // high bit indicates random sizes.
    mcl = (mcl - 1) & 7;

    // Wait for the HW to be ready
    while ((readTestCSR(7) & 3) != 0)
    {
        sleep(1);
    }

    if (vm["test-mode"].as<bool>())
    {
        writeTestCSR(4, 0xff);

        cout << "# Mem Bytes, Stride, Read GB/s, Write GB/s, VL0 lines, VH0 lines, VH1 lines" << endl;
        t_test_stats stats;
        uint64_t stride = 12;
        assert(runTest(cycles, stride, vc, mcl,
                       wrline_m, rdline_s,
                       1,  // Enable writes
                       1,  // Enable reads
                       &stats) == 0);

        cout << 0x100 * CL(1) << " "
             << stride << " "
             << boost::format("%.1f") % ((double(stats.read_cnt) * CL(1) / 0x40000000) / run_sec) << " "
             << boost::format("%.1f") % ((double(stats.write_cnt) * CL(1) / 0x40000000) / run_sec) << " "
             << stats.vl0_cnt << " "
             << stats.vh0_cnt << " "
             << stats.vh1_cnt << " "
             << endl;

        return 0;
    }

    uint64_t max_stride = uint64_t(vm["max-stride"].as<int>()) + 1;

    bool vcmap_all = vm["vcmap-all"].as<bool>();
    bool vcmap_enable = vm["vcmap-enable"].as<bool>();
    bool vcmap_dynamic = vm["vcmap-dynamic"].as<bool>();
    int32_t vcmap_fixed_vl0_ratio = int32_t(vm["vcmap-fixed"].as<int>());
    cout << "# MCL = " << mcl << endl
         << "# VC = " << vc << endl
         << "# VC Map enabled: " << (vcmap_enable ? "true" : "false") << endl;
    if (vcmap_enable)
    {
        cout << "# VC Map all: " << (vcmap_all ? "true" : "false") << endl
             << "# VC Map dynamic: " << (vcmap_dynamic ? "true" : "false") << endl;
        if (! vcmap_dynamic)
        {
            cout << "# VC Map fixed VL0 ratio: " << vcmap_fixed_vl0_ratio << " / 64" << endl;
        }
    }

    // Read
    cout << "#" << endl
         << "# Reads " << (rdline_s ? "" : "not ") << "cached" << endl
         << "# Mem Bytes, Stride, GB/s, VL0 lines, VH0 lines, VH1 lines" << endl;

    for (uint64_t mem_lines = 1; mem_lines * CL(1) <= n_bytes; mem_lines <<= 1)
    {
        writeTestCSR(4, mem_lines - 1);

        // Vary stride
        uint64_t stride_limit = (mem_lines < max_stride ? mem_lines : max_stride);
        for (uint64_t stride = 0; stride < stride_limit; stride += (1 + mcl))
        {
            t_test_stats stats;
            assert(runTest(cycles, stride, vc, mcl,
                           wrline_m, rdline_s,
                           0,  // No writes
                           1,  // Enable reads
                           &stats) == 0);

            cout << mem_lines * CL(1) << " "
                 << stride << " "
                 << boost::format("%.1f") % ((double(stats.read_cnt) * CL(1) / 0x40000000) / run_sec) << " "
                 << stats.vl0_cnt << " "
                 << stats.vh0_cnt << " "
                 << stats.vh1_cnt << " "
                 << endl;
        }
    }

    // Write
    cout << endl
         << endl
         << "# Writes " << (wrline_m ? "" : "not ") << "cached" << endl
         << "# Mem Bytes, Stride, GB/s, VL0 lines, VH0 lines, VH1 lines" << endl;

    for (uint64_t mem_lines = 1; mem_lines * CL(1) <= n_bytes; mem_lines <<= 1)
    {
        writeTestCSR(4, mem_lines - 1);

        // Vary stride
        uint64_t stride_limit = (mem_lines < max_stride ? mem_lines : max_stride);
        for (uint64_t stride = 0; stride < stride_limit; stride += (1 + mcl))
        {
            t_test_stats stats;
            assert(runTest(cycles, stride, vc, mcl,
                           wrline_m, rdline_s,
                           1,  // Enable writes
                           0,  // No reads
                           &stats) == 0);

            cout << mem_lines * CL(1) << " "
                 << stride << " "
                 << boost::format("%.1f") % ((double(stats.write_cnt) * CL(1) / 0x40000000) / run_sec) << " "
                 << stats.vl0_cnt << " "
                 << stats.vh0_cnt << " "
                 << stats.vh1_cnt << " "
                 << endl;
        }
    }

    // Throughput (independent read and write)
    cout << endl
         << endl
         << "# Reads " << (rdline_s ? "" : "not ") << "cached +"
         << " Writes " << (wrline_m ? "" : "not ") << "cached" << endl
         << "# Mem Bytes, Stride, GB/s, VL0 lines, VH0 lines, VH1 lines" << endl;

    for (uint64_t mem_lines = 1; mem_lines * CL(1) <= n_bytes; mem_lines <<= 1)
    {
        writeTestCSR(4, mem_lines - 1);

        // Vary stride
        uint64_t stride_limit = (mem_lines < max_stride ? mem_lines : max_stride);
        for (uint64_t stride = 0; stride < stride_limit; stride += (1 + mcl))
        {
            t_test_stats stats;
            assert(runTest(cycles, stride, vc, mcl,
                           wrline_m, rdline_s,
                           1,  // Enable writes
                           1,  // Enable reads
                           &stats) == 0);

            cout << mem_lines * CL(1) << " "
                 << stride << " "
                 << boost::format("%.1f") % ((double(stats.read_cnt) * CL(1) / 0x40000000) / run_sec) << " "
                 << boost::format("%.1f") % ((double(stats.write_cnt) * CL(1) / 0x40000000) / run_sec) << " "
                 << stats.vl0_cnt << " "
                 << stats.vh0_cnt << " "
                 << stats.vh1_cnt << " "
                 << endl;
        }
    }

    return 0;
}


int
TEST_MEM_PERF::runTest(uint64_t cycles,
                       uint64_t stride,
                       uint64_t vc,
                       uint64_t mcl,
                       uint64_t wrline_m,
                       uint64_t rdline_s,
                       uint64_t enable_writes,
                       uint64_t enable_reads,
                       t_test_stats* stats)
{
    uint64_t vl0_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_LINES);
    uint64_t vh0_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH0_LINES);
    uint64_t vh1_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH1_LINES);

    // Start the test
    writeTestCSR(0,
                 (cycles << 24) |
                 (stride << 8) |
                 (vc << 6) |
                 (mcl << 4) |
                 (wrline_m << 3) |
                 (rdline_s << 2) |
                 (enable_writes << 1) |
                 enable_reads);

    // Wait time for something to happen
    struct timespec ms;
    // Longer when simulating
    ms.tv_sec = (hwIsSimulated() ? 2 : 0);
    ms.tv_nsec = 2500000;

    uint64_t iter_state_end = 0;

    // Wait for test to signal it is complete
    while (*dsm == 0)
    {
        nanosleep(&ms, NULL);

        // Is the test done but not writing to DSM?  Could be a bug.
        uint8_t state = (readTestCSR(7) >> 8) & 255;
        if (state > 1)
        {
            if (iter_state_end++ == 5)
            {
                // Give up and signal an error
                break;
            }
        }
    }

    totalCycles += cycles;

    stats->read_cnt = readTestCSR(4);
    stats->write_cnt = readTestCSR(5);

    stats->vl0_cnt = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_LINES) - vl0_lines;
    stats->vh0_cnt = readCommonCSR(CCI_TEST::CSR_COMMON_VH0_LINES) - vh0_lines;
    stats->vh1_cnt = readCommonCSR(CCI_TEST::CSR_COMMON_VH1_LINES) - vh1_lines;

    if (*dsm != 1)
    {
        // Error!
        dbgRegDump(readTestCSR(7));
        return (*dsm == 1) ? 1 : 2;
    }

    *dsm = 0;

    return 0;
}


uint64_t
TEST_MEM_PERF::testNumCyclesExecuted()
{
    return totalCycles;
}


void
TEST_MEM_PERF::dbgRegDump(uint64_t r)
{
    cerr << "Test state:" << endl
         << "  State:           " << ((r >> 8) & 255) << endl
         << "  FIU C0 Alm Full: " << (r & 1) << endl
         << "  FIU C1 Alm Full: " << ((r >> 1) & 1) << endl;
}
