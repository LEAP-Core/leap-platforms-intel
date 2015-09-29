//
// Copyright (c) 2014, Intel Corporation
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

#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <errno.h>
#include <iostream>
#include <atomic>

#include "awb/provides/qa_driver.h"
#include "awb/provides/qa_driver_host_channels.h"
#include "awb/provides/physical_platform_defs.h"
#include "awb/provides/qa_device.h"


using namespace std;

// Handle to the QA device.  Useful when debugging.
static QA_DEVICE_CLASS *debugQADev;

// Receiver thread in loopback test
static void* LoopbackTestRecv(void *arg);

// ID of the accelerator.  For now we use a constant.  This should change
// to at least application-specific if not compilation-specific.
static const char* QA_AFU_ID = "12345678-0D82-4272-9AEF-FE5F84570612";


// ============================================
//           QA Physical Device
// ============================================

// ============================================
//           Class static functions
// These functions are necessary to ensure that the
// class constructor is non-blocking.
// ============================================

// ============================================
//           Class member functions
// ============================================

// constructor: set up hardware partition
QA_DEVICE_CLASS::QA_DEVICE_CLASS(
    PLATFORMS_MODULE p) :
        PLATFORMS_MODULE_CLASS(p),
        initReadComplete(),
        initWriteComplete(),
        afu(QA_AFU_ID)
{
    initReadComplete = false;
    initWriteComplete = false;

    readChunksAvail = 0;

    deviceSwitch = new COMMAND_SWITCH_DICTIONARY_CLASS("DEVICE_DICTIONARY");

    //
    // Check required properties
    //

    // UMF_CHUNK size is a power of 2
    assert((sizeof(UMF_CHUNK) & (sizeof(UMF_CHUNK) - 1)) == 0);
    // An array of UMF_CHUNKS completely fills a cache line
    assert((UMF_CHUNKS_PER_CL * sizeof(UMF_CHUNK)) == CL(1));

    debugQADev = this;
}


// destructor
QA_DEVICE_CLASS::~QA_DEVICE_CLASS()
{
    // cleanup
    Cleanup();
}


void
QA_DEVICE_CLASS::Init()
{
    // Disable AFU during configuration
    afu.WriteCSR(CSR_AFU_EN, 0);

    // How big are the FIFO buffers supposed to be?  Sizes are determined
    // in the hardware configuration and communicated in the DSM.  The hardware
    // fills the index of each buffer with ones.  Add one to get the size.
    writeBufferIdxMask = afu.ReadDSM(4 * sizeof(uint32_t));
    assert((writeBufferIdxMask & (writeBufferIdxMask + 1)) == 0);
    writeBufferBytes = (writeBufferIdxMask + 1) * CL(1);

    readBufferIdxMask = afu.ReadDSM(5 * sizeof(uint32_t));
    assert((readBufferIdxMask & (readBufferIdxMask + 1)) == 0);
    readBufferBytes = (readBufferIdxMask + 1) * CL(1);

    if (QA_DRIVER_DEBUG)
    {
        printf("FIFO from host cache lines:  %d\n", writeBufferBytes);
        printf("FIFO to host cache lines:    %d\n", readBufferBytes);
    }

    // create buffers
    readBuffer = afu.CreateSharedBuffer(readBufferBytes);
    writeBuffer = afu.CreateSharedBuffer(writeBufferBytes);

    if (readBuffer == NULL)
    {
        printf("Failed to create AFU readBuffer\n");
        exit(1);
    }

    if (writeBuffer == NULL)
    {
        printf("Failed to create AFU writeBuffer\n");
        exit(1);
    }

    readBufferStart = (UMF_CHUNK *)readBuffer->virtualAddress;
    readBufferEnd = (UMF_CHUNK *)(readBuffer->virtualAddress + readBufferBytes);
    readChunksNext = readBufferStart;

    writeBufferStart = (UMF_CHUNK *)writeBuffer->virtualAddress;
    writeBufferEnd = (UMF_CHUNK *)(writeBuffer->virtualAddress + writeBufferBytes);
    writeChunksNext = writeBufferStart;

    // Notice that we swap the read/write frames. Our read buffer is
    // the FPGA write buffer. Our write buffer is the FPGA read
    // buffer.
    afu.WriteCSR64(CSR_WRITE_FRAME, readBuffer->physicalAddress / CL(1));
    if (QA_DRIVER_DEBUG)
    {
        printf("Writing Host READ_FRAME base %p (line %p) ...\n", readBuffer->physicalAddress, readBuffer->physicalAddress);
    }

    afu.WriteCSR64(CSR_READ_FRAME, writeBuffer->physicalAddress / CL(1));
    if (QA_DRIVER_DEBUG)
    {
        printf("Writing Host WRITE_FRAME base %p (line %p) ...\n", writeBuffer->physicalAddress, writeBuffer->physicalAddress);
    }

    // Enable AFU (driver and test only)
    afu.WriteCSR(CSR_AFU_EN, 1);

    initReadComplete = true;
    initWriteComplete = true;

    sleep(1);
//    TestSend();
//    TestRecv();
//    TestLoopback();

    // Enable AFU (including user connection)
    afu.WriteCSR(CSR_AFU_EN, 3);
}

void
QA_DEVICE_CLASS::Uninit()
{
    // Disable AFU
    afu.WriteCSR(CSR_AFU_EN, 0);
}

void
QA_DEVICE_CLASS::Cleanup()
{
}

//
// Probe channel to determine whether fresh data exists.
//
bool
QA_DEVICE_CLASS::Probe()
{
    if (!initReadComplete) return false;

    if (readChunksAvail != 0)
    {
        return true;
    }

    //
    // Is there a new message?  The index of the newest active header is
    // written to the second 32 bit integer in DSM FIFO_STATE.
    //
    volatile uint32_t *newest_live_idx =
        (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_FIFO_STATE +
                                           sizeof(uint32_t));

    uint32_t idx = *newest_live_idx;

    // If the next message head pointer from the FPGA is the address
    // of the next chunk to read then there is no data available.
    if (&readBufferStart[idx * UMF_CHUNKS_PER_CL] == readChunksNext)
    {
        // No new messages
        return false;
    }

    return true;
}


//
// Blocking read
//
void
QA_DEVICE_CLASS::Read(
    void* buf,
    size_t nBytes)
{
    // nBytes must be a multiple of the UMF_CHUNK size
    assert((nBytes & (UMF_CHUNK_BYTES-1)) == 0);

    while (!initReadComplete)
    {
        sleep(1);
    }

    if (QA_DRIVER_DEBUG)
    {
        printf("READ needs %d bytes\n", nBytes);
    }

    size_t nChunks = nBytes / sizeof(UMF_CHUNK);

    while (nChunks != 0)
    {
        // Wait for a new message
        if (readChunksAvail == 0)
        {
            while (! Probe()) ;

            //
            // New message is ready.  Set up for reading it.
            //
            // First 32 bits hold the number of chunks in the message
            readChunksAvail = *(uint32_t*)readChunksNext;
            readChunksCurHead = readChunksNext;
            readChunksNext += 1;

            if (QA_DRIVER_DEBUG)
            {
                printf("New READ message with %lld chunks at %p\n", readChunksAvail, readChunksNext);
            }

            // The FPGA should never send an empty message
            if (readChunksAvail == 0)
            {
                readChunksNext -= (1 + UMF_CHUNKS_PER_CL);
                for (int i = 0; i < UMF_CHUNKS_PER_CL * 4; i += 1)
                {
                    printf("  FAIL (%p) 0x%016llx 0x%016llx\n", readChunksNext, uint64_t(*readChunksNext >> 64), uint64_t(*readChunksNext));
                    readChunksNext += 1;
                }
            }

            assert(readChunksAvail != 0);
        }

        //
        // How many chunks should be read on this trip through the loop?
        //

        // No more than are available
        size_t read_chunks = (nChunks <= readChunksAvail ? nChunks :
                                                           readChunksAvail);

        // Don't wrap around the ring buffer
        size_t chunks_to_buffer_end = readBufferEnd - readChunksNext;
        read_chunks = (read_chunks <= chunks_to_buffer_end ? read_chunks :
                                                             chunks_to_buffer_end);

        size_t read_bytes = read_chunks * sizeof(UMF_CHUNK);

        if (QA_DRIVER_DEBUG)
        {
            printf("  READ %d bytes from %p\n", read_bytes, readChunksNext);
        }

        // Copy the memory and update pointers
        memcpy(buf, readChunksNext, read_bytes);
        if (QA_DRIVER_DEBUG)
        {
            printf("  READ val 0x%016llx 0x%016llx\n", uint64_t(*readChunksNext >> 64), uint64_t(*readChunksNext));
        }
        buf = (void*)(uint64_t(buf) + read_bytes);
        readChunksNext += read_chunks;
        if (readChunksNext == readBufferEnd)
        {
            readChunksNext = readBufferStart;
        }

        readChunksAvail -= read_chunks;
        if (readChunksAvail == 0)
        {
            //
            // Finished a message
            //

            // Round chunk pointer up top the next cache line
            uint64_t cl_mask = CL(1) - 1;
            readChunksNext =
                (const UMF_CHUNK*)((uint64_t(readChunksNext) + CL(1) - 1) & ~cl_mask);
            if (readChunksNext == readBufferEnd)
            {
                readChunksNext = readBufferStart;
            }

            // Indicate that the last message was received by updating
            // the 2nd uint32_t of DSM POLL_STATE with the index of the
            // message currently being processed.
            volatile uint32_t *cur_read_idx =
                (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_POLL_STATE +
                                                   sizeof(uint32_t));
            *cur_read_idx = (readChunksNext - readBufferStart) / UMF_CHUNKS_PER_CL;

            if (QA_DRIVER_DEBUG)
            {
                printf("  Finished message group (next: %p, cur idx %ld)\n", readChunksNext, *cur_read_idx);
            }
        }
        else if (QA_DRIVER_DEBUG)
        {
            printf("  %lld READ chunks left (next: %p)\n", readChunksAvail, readChunksNext);
        }

        nChunks -= read_chunks;
    }

    atomic_thread_fence(std::memory_order_release);
}


//
// Write a message to the FPGA.
//
void
QA_DEVICE_CLASS::Write(
    const void* buf,
    size_t nBytes)
{
    // nBytes must be a multiple of the UMF_CHUNK size
    assert((nBytes & (UMF_CHUNK_BYTES-1)) == 0);

    if (nBytes == 0) return;

    while (!initWriteComplete)
    {
        if (QA_DRIVER_DEBUG)
        {
            printf("WRITE: waiting for init complete\n");
        }

        sleep(1);
    }

    if (QA_DRIVER_DEBUG)
    {
        printf("WRITE New %d byte write\n", nBytes);
    }

    // The FPGA updates a pointer to the oldest active entry in the ring buffer
    // to indicate when it is safe to overwrite the previous value.
    volatile uint32_t *oldest_live_idx =
        (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_FIFO_STATE);

    const UMF_CHUNK* src = (const UMF_CHUNK*)buf;

    size_t n_chunks = 0;
    while (nBytes)
    {
        // Spin until it is safe to write to the entry
        UMF_CHUNK* max_write_bound;
        do
        {
            // Index of the oldest live line.  Leave an empty spot before it
            // to differentiate between an empty ring buffer and a full buffer.
            size_t idx = (*oldest_live_idx - 1) & writeBufferIdxMask;

            // max_write_bound points to the first line to which writes are
            // not allowed due to unconsumed previous writes.
            max_write_bound = &writeBufferStart[idx * UMF_CHUNKS_PER_CL];
        }
        while (writeChunksNext == max_write_bound);

        if (QA_DRIVER_DEBUG)
        {
            size_t idx = uint64_t(max_write_bound - writeBufferStart) / UMF_CHUNKS_PER_CL;
            printf("  WRITE Bound is (at %p) is 0x%08lx\n", max_write_bound, idx);
        }

        // Start of a new message?
        if (n_chunks == 0)
        {
            // How many chunks in the next message?  The hardware chunk counter
            // is limited to 16 bits.
            n_chunks = nBytes / UMF_CHUNK_BYTES;
            if (n_chunks >= 0xffff)
            {
                n_chunks = 0xffff;
            }

            if (QA_DRIVER_DEBUG)
            {
                printf("  WRITE Start new message (at %p) with %d chunks\n", writeChunksNext, n_chunks);
            }

            *writeChunksNext++ = n_chunks;
        }

        // How much can be copied from the source buffer?
        size_t write_max_chunks;
        if (max_write_bound > writeChunksNext)
        {
            write_max_chunks = max_write_bound - writeChunksNext;
        }
        else
        {
            write_max_chunks = writeBufferEnd - writeChunksNext;
        }

        // Write the lesser of the number of chunks in the message and
        // the space available.
        size_t write_chunks = (n_chunks < write_max_chunks ? n_chunks :
                                                             write_max_chunks);
        size_t write_bytes = write_chunks * UMF_CHUNK_BYTES;

        memcpy(writeChunksNext, buf, write_bytes);

        buf = (const void*)((const uint8_t*)buf + write_bytes);
        nBytes -= write_bytes;
        n_chunks -= write_chunks;

        if (QA_DRIVER_DEBUG)
        {
            printf("    WRITE Copied %d chunks to %p, %d remain (%d bytes)\n", write_chunks, writeChunksNext, n_chunks, nBytes);
        }

        writeChunksNext += write_chunks;

        // Align writeChunksNext to a cache line.  This should only be needed
        // at the end of a message (n_chunks == 0).  The math is simpler than
        // branch prediction, so we just do it every time.
        uint64_t cl_mask = CL(1) - 1;
        writeChunksNext =
            (UMF_CHUNK*)((uint64_t(writeChunksNext) + CL(1) - 1) & ~cl_mask);

        // End of ring buffer?
        if (writeChunksNext == writeBufferEnd)
        {
            writeChunksNext = writeBufferStart;
        }

        // Update control word.  Need fence here...
        atomic_thread_fence(std::memory_order_release);

        // Indicate that new lines are available by updating the first uint32_t
        // of DSM POLL_STATE with a pointer to the head of the ring buffer.
        volatile uint32_t *newest_live_idx =
            (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_POLL_STATE);
        uint32_t next_line_idx = (writeChunksNext - writeBufferStart) /
                                 UMF_CHUNKS_PER_CL;
        *newest_live_idx = next_line_idx;

        if (QA_DRIVER_DEBUG)
        {
            printf("    WRITE Control newest idx (at %p) is 0x%08lx\n", newest_live_idx, next_line_idx);
        }
    }
}


void QA_DEVICE_CLASS::RegisterLogicalDeviceName(string name)
{
}


//
// Read from status register space.  Status registers are implemented in
// the FPGA side of this driver and are intended for debugging.
//
uint64_t
QA_DEVICE_CLASS::ReadSREG(uint32_t n)
{
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(DSM_OFFSET_SREG_RSP), 0, CL(1));

    // Write CSR to trigger a register read
    afu.WriteCSR(CSR_AFU_SREG_READ, n);

    // Wait for the response, signalled by the high bit in the line being set.
    while (afu.ReadDSM(DSM_OFFSET_SREG_RSP + CL(1) - sizeof(uint32_t)) == 0) ;

    return afu.ReadDSM64(DSM_OFFSET_SREG_RSP);
}


void
QA_DEVICE_CLASS::DebugDump()
{
    const uint32_t base = DSM_OFFSET_DEBUG_RSP;

    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(base), 0, CL(1));

    // Write CSR to trigger a state dump.
    afu.WriteCSR(CSR_AFU_TRIGGER_DEBUG, 1);

    // Wait for the response, signalled by the high bit in the line being set.
    while (afu.ReadDSM(base + CL(1) - sizeof(uint32_t)) == 0) ;

    printf("Debug READ DATA:\n");

    uint32_t flags = afu.ReadDSM(base);
    printf("\tScoreboard not full:       %d\n", flags & 1);
    flags >>= 1;
    printf("\tScoreboard not empty:      %d\n", flags & 1);
    flags >>= 1;

    printf("\tRead data requests:        %ld\n", afu.ReadDSM(base + 4));
    printf("\tRead data responses:       %ld\n", afu.ReadDSM(base + 8));
    printf("\tRecent reads [VA, value] (newest first):\n");
    for (int32_t i = 0; i < 4; i++)
    {
        const uint32_t base_offsets = base + 12;
        const uint32_t base_values = base_offsets + 4 * sizeof(uint32_t);

        printf("\t\t%p  0x%08lx (may not correspond)\n",
               getChunkAddressFromOffset(writeBuffer, afu.ReadDSM(base_offsets + i * sizeof(uint32_t))),
               afu.ReadDSM(base_values + i * sizeof(uint32_t)));
    }

    //
    // Tester module debug state
    //

    memset((void*)afu.DSMAddress(base), 0, CL(1));
    afu.WriteCSR(CSR_AFU_TRIGGER_DEBUG, 3);
    while (afu.ReadDSM(base + CL(1) - sizeof(uint32_t)) == 0) ;

    printf("\nDebug TESTER:\n");
    flags = afu.ReadDSM(base);
    printf("\tState:                     %d\n", flags & 3);
    flags >>= 2;
    printf("\ttx_enable:                 %d\n", flags & 1);
    flags >>= 1;
    printf("\ttx_rdy:                    %d\n", flags & 1);
    flags >>= 1;
    printf("\trx_enable:                 %d\n", flags & 1);
    flags >>= 1;
    printf("\trx_rdy:                    %d\n", flags & 1);
    flags >>= 1;
}


//
// Dump the current message being read from the FPGA by looking for the
// header, computing the length, and reading each UMF_CHUNK.
//
void
QA_DEVICE_CLASS::DebugDumpCurrentReadMessage()
{
    const UMF_CHUNK* p = readChunksCurHead;

    uint32_t n_chunks = *p;
    n_chunks = readChunksAvail;
    printf("Current READ message at %p has %d chunks:\n", p, n_chunks);
    printf("  Next read chunk at %p\n", readChunksNext);
    for (uint32_t i = 0; i < n_chunks; i += 1)
    {
        p += 1;
        printf("  %p: 0x%016llx 0x%016llx  (%d)\n", p, uint64_t(*p >> 64), uint64_t(*p), i);
    }
}


//
// Dump a history of messages seen in the FPGA on their way to the host.
// This may be useful when messages are corrupted.
//
// These are available only when debugging is enabled in the FPGA-side driver.
//
void
QA_DEVICE_CLASS::DebugDumpReadHistory()
{
    printf("Debug FIFO to HOST history:\n");

    const UMF_CHUNK* p = readChunksCurHead;

    // How many chunks in the current message?
    uint32_t n_chunks = *p;

    p = (const UMF_CHUNK*)afu.DSMAddress(DSM_OFFSET_DEBUG_RSP);

    // Dump chunks
    for (uint32_t i = 0; i < n_chunks; i += 1)
    {
        memset((void*)p, 0, CL(1));
        // The chunk index is sent in bits 8 and above
        afu.WriteCSR(CSR_AFU_TRIGGER_DEBUG, ((n_chunks - i) << 8) | 2);
        while (afu.ReadDSM(DSM_OFFSET_DEBUG_RSP + CL(1) - sizeof(uint32_t)) == 0) ;

        printf("  0x%016llx 0x%016llx  (%d)\n", uint64_t(*p >> 64), uint64_t(*p), i);
    }

    printf("\nSREG FIFO to HOST history:\n");
    // Dump chunks
    for (uint32_t i = 0; i < n_chunks; i += 1)
    {
        uint64_t r = ReadSREG(n_chunks - i);
        printf("                     0x%016llx  (%d)\n", r, i);
    }
}


#define TEST_MSG_CHUNKS 64

#if (CCI_SIMULATION != 0)
  // Don't send the full test length in simulation.  Note that messages about
  // throughput don't adjust and will be wrong.
  #define QA_TEST_LEN 20
#else
  // 1 GB tests
  #define QA_TEST_LEN 30
#endif

//
// TestSend --
//   Send a stream of data to the FPGA.  The FPGA will drop it.
//
void
QA_DEVICE_CLASS::TestSend()
{
    printf("SEND Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(0), 0, CL(1));

    // Put the FPGA in SINK mode.
    afu.WriteCSR(CSR_AFU_ENABLE_TEST, 1);

    // Wait for mode change.
    while (afu.ReadDSM(0) == 0) ;

    UMF_CHUNK *msg = new UMF_CHUNK[TEST_MSG_CHUNKS];
    for (int32_t i = 0; i < TEST_MSG_CHUNKS; i += 1)
    {
        msg[i] = i << 1;
    }
    const int msg_max_size = TEST_MSG_CHUNKS * UMF_CHUNK_BYTES;

    // First test: write a series of messages, growing in size
    for (int sz = UMF_CHUNK_BYTES; sz < msg_max_size; sz += UMF_CHUNK_BYTES)
    {
        Write(msg, sz);
    }

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    // Send 1GB
    for (uint64_t n = 0; n < (1LL << QA_TEST_LEN); n += msg_max_size)
    {
        Write(msg, msg_max_size);
    }

    gettimeofday(&finish, NULL);

    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Sent 1 GB of data in %.2f seconds (%.1f MB/s) \n", t, 1024.0 / t);

    // End test
    msg[0] = -1;
    Write(msg, UMF_CHUNK_BYTES);

    // End sends one loopback message
    Read(msg, UMF_CHUNK_BYTES);

    delete[] msg;
}

//
// TestRecv --
//   Receive an FPGA-generated stream of test data.
//
void
QA_DEVICE_CLASS::TestRecv()
{
    printf("RECEIVE Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(0), 0, CL(1));

    // Put the FPGA in SINK mode, requesting 1 GB of data.  The number of
    // chunks is sent in bits [31:2].
    uint32_t chunks = (1LL << QA_TEST_LEN) / UMF_CHUNK_BYTES;
    afu.WriteCSR(CSR_AFU_ENABLE_TEST, (chunks << 2) | 2);

    // Wait for mode change.
    while (afu.ReadDSM(0) == 0) ;

    UMF_CHUNK *msg = new UMF_CHUNK[TEST_MSG_CHUNKS];
    const int msg_max_size = TEST_MSG_CHUNKS * UMF_CHUNK_BYTES;

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    size_t bytes_left = chunks * UMF_CHUNK_BYTES;
    do
    {
        int sz = (bytes_left > msg_max_size) ? msg_max_size : bytes_left;
        bytes_left -= sz;

        Read(msg, sz);
    }
    while (bytes_left > 0);

    gettimeofday(&finish, NULL);

    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Received 1 GB of data in %.8f seconds (%.1f MB/s) \n", t, 1024.0 / t);

    delete[] msg;
}

//
// TestLoopback --
//   Test in which all messages sent to the FPGA are reflected back.
//
void
QA_DEVICE_CLASS::TestLoopback()
{
    printf("LOOPBACK Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(0), 0, CL(1));

    // Put the FPGA in SINK mode.
    afu.WriteCSR(CSR_AFU_ENABLE_TEST, 3);

    // Wait for mode change.
    while (afu.ReadDSM(0) == 0) ;

    pthread_t thread;
    pthread_create(&thread, NULL, LoopbackTestRecv, (void*)this);

    UMF_CHUNK *msg = new UMF_CHUNK[5127];
    const int msg_max_size = 5127 * UMF_CHUNK_BYTES;

    for (uint64_t i = 0; i < 5127; i++)
    {
        // Initialize to incrementing values in order to be able to test
        // responses.  Leave bit 0 clear because it indicates completion.
        msg[i] = i << 1;
    }

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    // Send 1GB
    for (uint64_t n = 0; n < (1LL << QA_TEST_LEN); n += msg_max_size)
    {
        Write(msg, msg_max_size);
    }

    gettimeofday(&finish, NULL);

    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Sent 1 GB of data in each direction in %.2f seconds (%.1f MB/s) \n", t, 1024.0 / t);

    // End test
    msg[0] = -1;
    Write(msg, UMF_CHUNK_BYTES);

    delete[] msg;

    void *res;
    pthread_join(thread, &res);
}


static void* LoopbackTestRecv(void *arg)
{
    QA_DEVICE dev = QA_DEVICE(arg);

    uint64_t expected_value = 0;

    UMF_CHUNK msg;
    do
    {
        dev->Read(&msg, UMF_CHUNK_BYTES);

        if ((uint32_t(msg) & 1) == 0)
        {
            if (msg != (expected_value << 1))
            {
                printf("Expected: 0x%016llx, got 0x%016llx\n", expected_value << 1, uint64_t(msg));
                dev->DebugDumpCurrentReadMessage();
                exit(1);
            }

            expected_value += 1;
            if (expected_value == 5127)
            {
                expected_value = 0;
            }
        }
    }
    while ((uint32_t(msg) & 1) == 0);

    printf(" Loopback thread exiting...\n");
    return NULL;
}
