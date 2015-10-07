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

// AAL defines ASSERT, which will be redefined by LEAP
#undef ASSERT

#include "awb/provides/qa_driver_host_channels.h"
#include "awb/provides/physical_platform_defs.h"
#include "awb/provides/qa_device.h"


using namespace std;

// Handle to the QA device.  Useful when debugging.
static QA_DEVICE_CLASS *debugQADev;

// Receiver thread in loopback test
static void* LoopbackTestRecv(void *arg);


// ============================================
//           QA Physical Device
// ============================================


QA_DEVICE_CLASS::QA_DEVICE_CLASS(
    PLATFORMS_MODULE p,
    AFU_CLASS& afuDev) :
        PLATFORMS_MODULE_CLASS(p),
        initReadComplete(),
        initWriteComplete(),
        afu(afuDev),
        readFillNext(0),
        readNext(0),
        readBytesAvail(0),
        enableTests(false)
{
    initReadComplete = false;
    initWriteComplete = false;

    debugQADev = this;
}


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

    uint64_t readBufferIdxMask = afu.ReadDSM(5 * sizeof(uint32_t));
    assert((readBufferIdxMask & (readBufferIdxMask + 1)) == 0);
    readBufferBytes = (readBufferIdxMask + 1) * CL(1);

    if (QA_DRIVER_DEBUG)
    {
        printf("FIFO from host buffer bytes:  %d\n", writeBufferBytes);
        printf("FIFO to host buffer bytes:    %d\n", readBufferBytes);
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

    // Initialize pointers to the buffers
    readBufferStart = (uint8_t *)readBuffer->virtualAddress;
    readBufferEnd = (uint8_t *)(readBuffer->virtualAddress + readBufferBytes);
    readFillNext = readBufferStart;
    readNext = readBufferStart;

    writeBufferStart = (uint8_t *)writeBuffer->virtualAddress;
    writeBufferEnd = (uint8_t *)(writeBuffer->virtualAddress + writeBufferBytes);
    writeNext = writeBufferStart;

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
    if (enableTests)
    {
        TestSend();
        TestRecv();
        TestLoopback();
    }

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
    // Do we already know about available data from a previous probe?
    if (readFillNext != readNext)
    {
        return true;
    }

    if (!initReadComplete) return false;

    //
    // Is there a new message?  The index of the newest active header is
    // written to the second 32 bit integer in DSM FIFO_STATE.
    //
    volatile uint32_t *newest_live_idx =
        (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_FIFO_STATE +
                                           sizeof(uint32_t));

    // Hardware's index is offset in lines.  Convert to bytes.
    uint32_t idx = CL(*newest_live_idx);
    readFillNext = &readBufferStart[idx];

    // If the next message head pointer from the FPGA is the address
    // of the next line to read then there is no data available.
    return (readFillNext != readNext);
}


//
// Read lines
//
size_t
QA_DEVICE_CLASS::Read(
    void* buf,
    size_t nBytes,
    bool block)
{
    if (readBytesAvail >= nBytes)
    {
        // We already know there is enough data buffered to satisfy the
        // request.
        memcpy(buf, readNext, nBytes);
        UpdateReadPtr(nBytes);
        return nBytes;
    }

    while (!initReadComplete)
    {
        sleep(1);
    }

    if (QA_DRIVER_DEBUG)
    {
        printf("READ needs %d bytes\n", nBytes);
    }

    size_t bytes_read = 0;

    while (nBytes != 0)
    {
        // Wait for a new message
        while (! Probe())
        {
            // If not blocking then return whatever was available.
            if (! block) return bytes_read;
        }

        //
        // How many bytes should be read on this trip through the loop?
        //

        // Be careful to note wrapping around the ring buffer.
        if (readNext <= readFillNext)
        {
            readBytesAvail = readFillNext - readNext;
        }
        else
        {
            readBytesAvail = readBufferEnd - readNext;
        }

        // Read no more than are available
        size_t read_bytes = (nBytes <= readBytesAvail ? nBytes : readBytesAvail);

        if (QA_DRIVER_DEBUG)
        {
            printf("  READ %d bytes from %p\n", read_bytes, readNext);
        }

        // Copy the memory and update pointers
        memcpy(buf, readNext, read_bytes);
        buf = (void*)(uint64_t(buf) + read_bytes);

        UpdateReadPtr(read_bytes);
        nBytes -= read_bytes;
    }
}


//
// Write a message to the FPGA.
//
void
QA_DEVICE_CLASS::Write(
    const void* buf,
    size_t nBytes)
{
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

    const uint8_t* src = (const uint8_t*)buf;

    while (nBytes)
    {
        // Spin until it is safe to write to the entry
        uint8_t* max_write_bound;
        do
        {
            // Index of the oldest live line.  Leave an empty spot before it
            // to differentiate between an empty ring buffer and a full buffer.
            size_t idx = (*oldest_live_idx - 1) & writeBufferIdxMask;

            // max_write_bound points to the first line to which writes are
            // not allowed due to unconsumed previous writes.
            max_write_bound = &writeBufferStart[CL(idx)];
        }
        while (writeNext == max_write_bound);

        if (QA_DRIVER_DEBUG)
        {
            size_t idx = uint64_t(max_write_bound - writeBufferStart) / CL(1);
            printf("  WRITE Bound (at %p) is 0x%08lx\n", max_write_bound, idx);
        }

        // How much can be copied from the source buffer?
        size_t write_max_bytes;
        if (max_write_bound > writeNext)
        {
            write_max_bytes = max_write_bound - writeNext;
        }
        else
        {
            write_max_bytes = writeBufferEnd - writeNext;
        }

        // Write the lesser of the size of the message and the space available.
        size_t write_bytes = (nBytes <= write_max_bytes ? nBytes :
                                                          write_max_bytes);
        memcpy(writeNext, src, write_bytes);

        src = src + write_bytes;
        nBytes -= write_bytes;

        if (QA_DRIVER_DEBUG)
        {
            printf("    WRITE Copied %d bytes to %p, %d remain\n", write_bytes, writeNext, nBytes);
        }

        writeNext += write_bytes;

        // End of ring buffer?
        if (writeNext == writeBufferEnd)
        {
            writeNext = writeBufferStart;
        }

        // Update control word.  Need fence here...
        atomic_thread_fence(std::memory_order_release);

        // Indicate that new lines are available by updating the first uint32_t
        // of DSM POLL_STATE with a pointer to the head of the ring buffer.
        uint32_t *newest_live_idx =
            (uint32_t*)afu.DSMAddress(DSM_OFFSET_POLL_STATE);
        uint32_t next_line_idx = (writeNext - writeBufferStart) / CL(1);
        *newest_live_idx = next_line_idx;

        if (QA_DRIVER_DEBUG)
        {
            printf("    WRITE Control newest idx (at %p) is 0x%08lx\n", newest_live_idx, next_line_idx);
        }
    }
}


void
QA_DEVICE_CLASS::Flush()
{
    // Is there a partially written line?
    size_t partial = size_t(writeNext) & (CL(1) - 1);
    if (partial != 0)
    {
        size_t rem = CL(1) - partial;

        memset(writeNext, 0, rem);
        writeNext += rem;

        // Update the FPGA-side pointer.
        volatile uint32_t *newest_live_idx =
            (volatile uint32_t*)afu.DSMAddress(DSM_OFFSET_POLL_STATE);
        uint32_t next_line_idx = (writeNext - writeBufferStart) / CL(1);
        *newest_live_idx = next_line_idx;

        if (QA_DRIVER_DEBUG)
        {
            printf("    FLUSH Control newest idx (at %p) is 0x%08lx\n", newest_live_idx, next_line_idx);
        }
    }
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


#define TEST_MSG_BYTES 8192

#if (CCI_SIMULATION != 0)
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
    printf("SEND to FPGA Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(0), 0, CL(1));

    // Put the FPGA in SINK mode.
    afu.WriteCSR(CSR_AFU_ENABLE_TEST, 1);

    // Wait for mode change.
    while (afu.ReadDSM(0) == 0) ;

    uint8_t *msg = new uint8_t[TEST_MSG_BYTES];
    for (int32_t i = 0; i < TEST_MSG_BYTES; i += 1)
    {
        msg[i] = i << 1;
    }

    // First test: write a series of messages, growing in size
    for (size_t sz = CL(1); sz < TEST_MSG_BYTES; sz *= 2)
    {
        Write(msg, sz);
    }

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    // Send data
    for (uint64_t n = 0; n < (1LL << QA_TEST_LEN); n += TEST_MSG_BYTES)
    {
        Write(msg, TEST_MSG_BYTES);
    }

    gettimeofday(&finish, NULL);

    double xmit_gb = (1LL << QA_TEST_LEN) / 1073741824.0;
    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Sent %.3f GB of data in %.2f seconds (%.3f GB/s) \n",
           xmit_gb, t, xmit_gb / t);

    // End test
    msg[0] = -1;
    Write(msg, CL(1));

    // End sends one loopback message
    Read(msg, CL(1));

    delete[] msg;
}

//
// TestRecv --
//   Receive an FPGA-generated stream of test data.
//
void
QA_DEVICE_CLASS::TestRecv()
{
    printf("RECEIVE from FPGA Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.DSMAddress(0), 0, CL(1));

    // Put the FPGA in SINK mode, requesting 1 GB of data.  The number of
    // chunks is sent in bits [31:2].
    uint64_t lines = (1LL << QA_TEST_LEN) / CL(1);
    afu.WriteCSR(CSR_AFU_ENABLE_TEST, (lines << 2) | 2);

    // Wait for mode change.
    while (afu.ReadDSM(0) == 0) ;

    uint8_t *msg = new uint8_t[TEST_MSG_BYTES];

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    size_t bytes_left = CL(lines);
    do
    {
        size_t sz = (bytes_left > TEST_MSG_BYTES) ? TEST_MSG_BYTES : bytes_left;
        bytes_left -= sz;

        Read(msg, sz);
    }
    while (bytes_left > 0);

    gettimeofday(&finish, NULL);

    double xmit_gb = (1LL << QA_TEST_LEN) / 1073741824.0;
    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Received %.3f GB of data in %.8f seconds (%.3f GB/s) \n",
           xmit_gb, t, xmit_gb / t);

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

    uint8_t *msg = new uint8_t[TEST_MSG_BYTES];
    for (int32_t i = 0; i < TEST_MSG_BYTES; i += 1)
    {
        msg[i] = i << 1;
    }

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    // Send data
    for (uint64_t n = 0; n < (1LL << QA_TEST_LEN) - TEST_MSG_BYTES ; n += TEST_MSG_BYTES)
    {
        Write(msg, TEST_MSG_BYTES);
    }

    // End test
    msg[TEST_MSG_BYTES - CL(1)] = -1;
    Write(msg, TEST_MSG_BYTES);

    delete[] msg;

    void *res;
    pthread_join(thread, &res);

    gettimeofday(&finish, NULL);

    double xmit_gb = (1LL << QA_TEST_LEN) / 1073741824.0;
    struct timeval elapsed;
    timersub(&finish, &start, &elapsed);
    double t = (1.0 * elapsed.tv_sec) + (0.000001 * elapsed.tv_usec);
    printf(" *** Sent %.3f GB of data in each direction in %.2f seconds (%.3f GB/s) \n",
           xmit_gb, t, 2.0 * xmit_gb / t);

}


static void* LoopbackTestRecv(void *arg)
{
    QA_DEVICE dev = QA_DEVICE(arg);

    uint64_t expected_value = 0;

    uint8_t *msg = new uint8_t[TEST_MSG_BYTES];
    do
    {
        dev->Read(msg, TEST_MSG_BYTES);
    }
    while ((msg[TEST_MSG_BYTES - CL(1)] & 1) == 0);

    delete[] msg;

    printf(" Loopback thread exiting...\n");
    return NULL;
}
