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

#include "test_mem_perf.h"
#include <time.h>


bool
TEST_MEM_PERF::initMem(bool enableWarmup)
{
    // Allocate memory for control
    dsm = (uint64_t*) this->malloc(4096);
    if (dsm == NULL) return false;
    memset((void*)dsm, 0, 4096);

    // Allocate memory for read/write tests.  The HW indicates the size
    // of the memory buffer in CSR 0.
    uint64_t addr_info = readTestCSR(0);
    
    // Low 16 bits holds the number of line address bits required
    buffer_bytes = CL(1) * (1LL << uint16_t(addr_info));
    cout << "# Allocating two " << buffer_bytes / (1024 * 1024) << "MB test buffers..." << endl;

    // Allocate two buffers worth plus an extra 2MB page to allow for alignment
    // changes.
    rd_mem = (uint64_t*) this->malloc(2 * buffer_bytes + 2048 * 1024);
    if (rd_mem == NULL) return false;
    // Align to minimize cache conflicts
    wr_mem = (uint64_t*) (uint64_t(rd_mem) + buffer_bytes + 512 * CL(1));

    memset((void*)rd_mem, 0, buffer_bytes);
    memset((void*)wr_mem, 0, buffer_bytes);

    //
    // Configure the HW test
    //
    writeTestCSR(1, uint64_t(dsm) / CL(1));

    if (enableWarmup)
    {
        warmUp(wr_mem, buffer_bytes / 2);
        warmUp(rd_mem, buffer_bytes);
    }

    writeTestCSR(2, uint64_t(rd_mem) / CL(1));
    writeTestCSR(3, uint64_t(wr_mem) / CL(1));

    // Wait for the HW to be ready
    while ((readTestCSR(7) & 3) != 0)
    {
        sleep(1);
    }

    return true;
}


int
TEST_MEM_PERF::runTest(const t_test_config* config, t_test_stats* stats)
{
    // Ensure that the requested number of cycles and the actual executed
    // cycle count fit in a 32 bit counter.  We assume the test won't run
    // for more than 2x the requested length, which had better be the case.
    assert(config->cycles == (config->cycles & 0x7fffffff));

    assert((config->mcl & config->stride) == 0);
    assert((config->buf_lines & (config->buf_lines - 1)) == 0);

    // Read baseline values of counters.  We'll read them again after the
    // test and compute the difference.
    stats->read_cache_line_hits = readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_RD_HITS);
    stats->write_cache_line_hits = readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_WR_HITS);
    stats->vl0_rd_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_RD_LINES);
    stats->vl0_wr_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_WR_LINES);
    stats->vh0_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH0_LINES);
    stats->vh1_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH1_LINES);

    // Mask of active memory window
    writeTestCSR(4, config->buf_lines - 1);
    // Offered load (cycles between write and read requests)
    writeTestCSR(6, (uint64_t(config->wr_interval) << 8) |
                    uint64_t(config->rd_interval));

    // Start the test
    writeTestCSR(5, (uint64_t(config->stride) << 8) |
                    (uint64_t(config->vc) << 6) |
                    (uint64_t(config->mcl) << 4) |
                    (uint64_t(config->wrline_m) << 3) |
                    (uint64_t(config->rdline_s) << 2) |
                    (uint64_t(config->enable_writes) << 1) |
                    uint64_t(config->enable_reads));
    writeTestCSR(0, config->cycles);

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

    stats->actual_cycles = *dsm;
    // Run length in seconds
    stats->run_sec = double(stats->actual_cycles) /
                     (double(readCommonCSR(CSR_COMMON_FREQ)) * 1000.0 * 1000.0);

    totalCycles += config->cycles;

    stats->read_lines = readTestCSR(4);
    stats->write_lines = readTestCSR(5);

    stats->read_cache_line_hits = readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_RD_HITS) - stats->read_cache_line_hits;
    stats->write_cache_line_hits = readCommonCSR(CCI_TEST::CSR_COMMON_CACHE_WR_HITS) - stats->write_cache_line_hits;
    stats->vl0_rd_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_RD_LINES) - stats->vl0_rd_lines;
    stats->vl0_wr_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VL0_WR_LINES) - stats->vl0_wr_lines;
    stats->vh0_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH0_LINES) - stats->vh0_lines;
    stats->vh1_lines = readCommonCSR(CCI_TEST::CSR_COMMON_VH1_LINES) - stats->vh1_lines;

    // Inflight counters are in DSM.  Convert packets to lines.
    stats->read_max_inflight_lines = (dsm[1] & 0xffffffff) * (config->mcl + 1);
    stats->write_max_inflight_lines = (dsm[1] >> 32) * (config->mcl + 1);

    if (stats->actual_cycles == 0)
    {
        // Error!
        dbgRegDump(readTestCSR(7));
        return 1;
    }

    // Convert read/write counts to packets
    uint64_t read_packets = stats->read_lines / (config->mcl + 1);
    uint64_t write_packets = stats->write_lines / (config->mcl + 1);

    stats->read_average_latency = (read_packets ? dsm[2] / read_packets : 0);
    stats->write_average_latency = (write_packets ? dsm[3] / write_packets : 0);

    *dsm = 0;

    return 0;
}


void
TEST_MEM_PERF::warmUp(void* buf, uint64_t n_bytes)
{
    // Warm up VTP by stepping across 4K pages
    t_test_config config;
    memset(&config, 0, sizeof(config));

    // Read from the buffer to be warmed up
    writeTestCSR(2, uint64_t(buf) / CL(1));
    writeTestCSR(3, uint64_t(buf) / CL(1));

    // Give the warm-up code 10x the number of cycles needed to request
    // reads of each page.  The later pages don't matter much anyway, so
    // this is plenty of time for the early part of the buffer.
    config.cycles = 10 * n_bytes / 4096;
    config.buf_lines = n_bytes / CL(1);
    config.stride = 4096 / CL(1);
    config.vc = 2;
    config.enable_writes = 1;
    config.wrline_m = 1;

    t_test_stats stats;
    runTest(&config, &stats);

    // Warm up cache by writing the first 2K lines in the buffer
    config.cycles = 32768;
    config.buf_lines = 2048;
    config.stride = 1;
    config.vc = 1;
    runTest(&config, &stats);
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
