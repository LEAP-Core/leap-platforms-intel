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

#include "platforms-module.h"
#include "default-switches.h"

#include "awb/provides/qa_driver.h"
#include "awb/provides/physical_platform_defs.h"
#include "awb/provides/qa_device.h"


using namespace std;

extern GLOBAL_ARGS globalArgs;

static void* LoopbackTestRecv(void *arg);


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
        afu(EXPECTED_AFU_ID, CCI_SIMULATION ? CCI_ASE : CCI_DIRECT)
{
    initReadComplete = false;
    initWriteComplete = false;
    readFrameNumber = 0;
    writeFrameNumber = 0;
    readChunksTotal = 0;
    readChunkNumber = 0;
    deviceSwitch = new COMMAND_SWITCH_DICTIONARY_CLASS("DEVICE_DICTIONARY");
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

    string executionDirectory = "";
    char * leapExecutionDirectory = getenv("LEAP_EXECUTION_DIRECTORY");

    // disable AFU
    cout << "Attempting to disable afu" << endl;
    afu.write_csr(CSR_AFU_EN, 0);

    // create buffers                                                                                                                                                                                       
    readBuffer = afu.create_buffer_aligned(BUFFER_SIZE);
    writeBuffer = afu.create_buffer_aligned(BUFFER_SIZE);

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

    // Notic that we swap the read/write frames. Our read buffer is
    // the FPGA write buffer. Our write buffer is the FPGA read
    // buffer.
    afu.write_csr_64(CSR_WRITE_FRAME, readBuffer->physical_address);
    if (QA_DRIVER_DEBUG)
    {
        printf("Writing Host READ_FRAME base %p (line %p) ...\n", readBuffer->physical_address, CACHELINE_ALIGNED_ADDR(readBuffer->physical_address));
    }

    afu.write_csr_64(CSR_READ_FRAME, writeBuffer->physical_address);
    if (QA_DRIVER_DEBUG)
    {
        printf("Writing Host WRITE_FRAME base %p (line %p) ...\n", writeBuffer->physical_address, CACHELINE_ALIGNED_ADDR(writeBuffer->physical_address));
    }

    // enable AFU                                                                                                                                                                                           
    afu.write_csr(CSR_AFU_EN, 1);

    initReadComplete = true;
    initWriteComplete = true;

    TestSend();
    TestRecv();
    TestLoopback();
}

// override default chain-uninit method because
// we need to do something special
void
QA_DEVICE_CLASS::Uninit()
{

}

// cleanup: close the pipe.  The other side will exit.
void
QA_DEVICE_CLASS::Cleanup()
{

}

// probe pipe to look for fresh data
bool
QA_DEVICE_CLASS::Probe()
{
    if (!initReadComplete) return false;

    if(readChunksTotal != 0)
    {
        return true;
    }

    UMF_CHUNK controlChunk = *(getChunkAddress(readBuffer, readFrameNumber, 0));

    if (QA_DRIVER_DEBUG)
    {
        if(controlChunk != 0)
        {
            printf("Probe control chunk %llx\n", controlChunk);
        }
    }
        
    return (controlChunk & 0x1);

}

// blocking read
void
QA_DEVICE_CLASS::Read(
    void* buf,
    size_t count)
{
    while(!initReadComplete) 
    {
        sleep(1);
    }

    int chunkNumber = 0, bytesRead = 0;
    UMF_CHUNK controlChunk = 0;

    // I really only want to deal in chunks for now.
    assert(count % UMF_CHUNK_BYTES == 0);

    if (QA_DRIVER_DEBUG)
    {
        printf("READ needs %d bytes\n", count);
    }

    if(readChunksTotal == 0)
    {
        do
        {
            controlChunk = *getChunkAddress(readBuffer, readFrameNumber, chunkNumber);            
            if (QA_DRIVER_DEBUG)
            {
                printf("READ needs sppinning for control chunk for frame %d: %p -> %llx\n", readFrameNumber, getChunkAddress(readBuffer, readFrameNumber, chunkNumber), controlChunk);
            }

            if(!(controlChunk & 0x1))
            {
                sleep(1);
            }

        } while(!(controlChunk & 0x1));

        readChunksTotal = ((controlChunk) >> 1) & 0xfff;
        readChunkNumber = 0;
    }

    for(;  (bytesRead < count) && (readChunkNumber < readChunksTotal); bytesRead += UMF_CHUNK_BYTES)
    {
        readChunkNumber++;
        *((UMF_CHUNK *)(buf+bytesRead)) = *getChunkAddress(readBuffer, readFrameNumber, readChunkNumber);

        if (QA_DRIVER_DEBUG)
        {
            printf("Read chunk %p -> 0x%016llx %016llx, chunk number: %d, chunk total: %d\n",
                   getChunkAddress(readBuffer, readFrameNumber, readChunkNumber),
                   uint64_t(*getChunkAddress(readBuffer, readFrameNumber, readChunkNumber) >> 64),
                   uint64_t(*getChunkAddress(readBuffer, readFrameNumber, readChunkNumber)),
                   readChunkNumber, readChunksTotal);
        }
    }

    if(readChunkNumber == readChunksTotal)
    {
        // free block
        if (QA_DRIVER_DEBUG)
        {
            printf("Read frees frame number %d\n",  readFrameNumber);
        }

        *getChunkAddress(readBuffer, readFrameNumber, 0) = 0;
        readFrameNumber = (readFrameNumber + 1) % FRAME_NUMBER;
        readChunksTotal = 0; // No more data left.
        // Got any data remaining to read? if so tail recurse!
        if(bytesRead < count)
        {
            if (QA_DRIVER_DEBUG)
            {
                printf("Tail recurse for read needed\n");
            }

            Read(buf+bytesRead, count - bytesRead);
        }
    }
}

// write
void
QA_DEVICE_CLASS::Write(
    const void* buf,
    size_t count)
{
    if (count == 0) return;

    int chunkNumber = 0;
    volatile UMF_CHUNK *controlAddr = getChunkAddress(writeBuffer, writeFrameNumber, chunkNumber);
    UMF_CHUNK controlChunk;
    while (!initWriteComplete) 
    {  
        if (QA_DRIVER_DEBUG)
        {
            printf("WRITE: waiting for init complete\n");
        }
 
        sleep(1);
    }
   
    assert(count % UMF_CHUNK_BYTES == 0);
    assert(count < FRAME_CHUNKS * UMF_CHUNK_BYTES);

    // Spin for next frame.
    do
    {
        controlChunk = *controlAddr;
        if (QA_DRIVER_DEBUG)
        {
            printf("WRITE: Control chunk %p is %llx \n", controlAddr, controlChunk);
        }
    } while(controlChunk & 0x1);


    for(int offset = 0;  offset < count; offset += UMF_CHUNK_BYTES)
    {
        chunkNumber++;
        volatile UMF_CHUNK *chunkAddr = getChunkAddress(writeBuffer, writeFrameNumber, chunkNumber);
        *chunkAddr = *((UMF_CHUNK *)(buf+offset));
        if (QA_DRIVER_DEBUG)
        {
            uint32_t chunk_offset = getChunkOffset(writeFrameNumber, chunkNumber);
            printf("WRITE writing chunk address %p (offset 0x%08lx) 0%016llx %016llx\n", chunkAddr, chunk_offset, *chunkAddr, *((UMF_CHUNK *)(buf+offset))); 
        }
    }

    // Write control word.  Need fence here...
    atomic_thread_fence(std::memory_order_release);

    controlChunk = (chunkNumber << 1) | 0xdeadbeef0001;
    *controlAddr = controlChunk;

    if (QA_DRIVER_DEBUG)
    {
        printf("WRITE Control chunk %p is %llx \n", controlAddr, controlChunk);
    }

    writeFrameNumber = (writeFrameNumber + 1) % FRAME_NUMBER;   
}

void QA_DEVICE_CLASS::RegisterLogicalDeviceName(string name)
{

}

void
QA_DEVICE_CLASS::DebugDump()
{
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.dsm_address(0), 0, CL(1));

    // Write CSR to trigger a state dump.
    afu.write_csr(CSR_AFU_TRIGGER_DEBUG, 1);

    // Wait for the response, signalled by the high bit in the line being set.
    while (afu.read_dsm(CL(1) - sizeof(uint32_t)) == 0) ;

    printf("Debug READ DATA:\n");

    printf("\tFrame control state:\n");
    for (int i = 0; i < FRAME_NUMBER; i++)
    {
        volatile UMF_CHUNK* frame = getChunkAddress(writeBuffer, i, 0);
        printf("\t\t%p:  0x%016llx\n", frame, uint64_t(*frame));
    }
    printf("\n");

    uint32_t flags = afu.read_dsm(0);
    printf("\tScoreboard not full:       %d\n", flags & 1);
    flags >>= 1;
    printf("\tScoreboard not empty:      %d\n", flags & 1);
    flags >>= 1;
    printf("\tFrame release not full:    %d\n", flags & 1);
    flags >>= 1;
    printf("\tFrame release write req:   %d\n", flags & 1);
    flags >>= 1;

    printf("\tRead data requests:        %ld\n", afu.read_dsm(4));
    printf("\tRead data responses:       %ld\n", afu.read_dsm(8));
    printf("\tRecent reads [VA, value] (newest first):\n");
    for (int32_t i = 0; i < 4; i++)
    {
        const uint32_t base_offsets = 12;
        const uint32_t base_values = base_offsets + 4 * sizeof(uint32_t);

        printf("\t\t%p  0x%08lx (may not correspond)\n",
               getChunkAddressFromOffset(writeBuffer, afu.read_dsm(base_offsets + i * sizeof(uint32_t))),
               afu.read_dsm(base_values + i * sizeof(uint32_t)));
    }


    //
    // Frame release module debug state
    //

    memset((void*)afu.dsm_address(0), 0, CL(1));
    afu.write_csr(CSR_AFU_TRIGGER_DEBUG, 3);
    while (afu.read_dsm(CL(1) - sizeof(uint32_t)) == 0) ;

    printf("\nDebug FRAME RELEASE:\n");
    printf("\tWrite grant without req:   %s\n", ((afu.read_dsm(0) & 1) == 0) ? "Ok" : "ERROR");
    printf("\tNumber of cleared frames:  %d\n", uint16_t(afu.read_dsm(2)));
    printf("\tWrite credit last offset:  %p\n",
           getChunkAddressFromOffset(writeBuffer, afu.read_dsm(4)));


    //
    // Tester module debug state
    //

    memset((void*)afu.dsm_address(0), 0, CL(1));
    afu.write_csr(CSR_AFU_TRIGGER_DEBUG, 2);
    while (afu.read_dsm(CL(1) - sizeof(uint32_t)) == 0) ;

    printf("\nDebug TESTER:\n");
    flags = afu.read_dsm(0);
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
// TestSend --
//   Send a stream of data to the FPGA.  The FPGA will drop it.
//
void
QA_DEVICE_CLASS::TestSend()
{
    printf("SEND Test...\n");
    // The FPGA will write to DSM line 0.  Clear it first.
    memset((void*)afu.dsm_address(0), 0, CL(1));

    // Put the FPGA in SINK mode.
    afu.write_csr(CSR_AFU_ENABLE_TEST, 1);

    // Wait for mode change.
    while (afu.read_dsm(0) == 0) ;

    UMF_CHUNK *msg = new UMF_CHUNK[FRAME_CHUNKS];
    const int msg_max_size = FRAME_CHUNKS * UMF_CHUNK_BYTES / 2;
    memset((void*)msg, 0, msg_max_size);

    // First test: write a series of messages, growing in size
    for (int sz = UMF_CHUNK_BYTES; sz < msg_max_size; sz <<= 1)
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
    for (uint64_t n = 0; n < (1LL << 30); n += msg_max_size)
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
    memset((void*)afu.dsm_address(0), 0, CL(1));

    // Put the FPGA in SINK mode, requesting 1 GB of data.  The number of
    // chunks is sent in bits [31:2].
    uint32_t chunks = (1LL << 30) / UMF_CHUNK_BYTES;
    afu.write_csr(CSR_AFU_ENABLE_TEST, (chunks << 2) | 2);

    // Wait for mode change.
    while (afu.read_dsm(0) == 0) ;

    UMF_CHUNK *msg = new UMF_CHUNK[FRAME_CHUNKS];
    const int msg_max_size = FRAME_CHUNKS * UMF_CHUNK_BYTES / 2;

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
    printf(" *** Received 1 GB of data in %.8f seconds (%.8f MB/s) \n", t, 1024.0 / t);

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
    memset((void*)afu.dsm_address(0), 0, CL(1));

    // Put the FPGA in SINK mode.
    afu.write_csr(CSR_AFU_ENABLE_TEST, 3);

    // Wait for mode change.
    while (afu.read_dsm(0) == 0) ;

    pthread_t thread;
    pthread_create(&thread, NULL, LoopbackTestRecv, (void*)this);

    UMF_CHUNK *msg = new UMF_CHUNK[FRAME_CHUNKS];
    const int msg_max_size = FRAME_CHUNKS * UMF_CHUNK_BYTES / 2;
    memset((void*)msg, 0, msg_max_size);

    //
    // Measure performance
    //
    struct timeval start;
    struct timeval finish;
    gettimeofday(&start, NULL);

    // Send 1GB
    for (uint64_t n = 0; n < (1LL << 30); n += msg_max_size)
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

    // End sends one loopback message
    Read(msg, UMF_CHUNK_BYTES);

    delete[] msg;

    void *res;
    pthread_join(thread, &res);
}


static void* LoopbackTestRecv(void *arg)
{
    QA_DEVICE dev = QA_DEVICE(arg);

    unsigned char msg[UMF_CHUNK_BYTES];
    do
    {
        dev->Read(msg, UMF_CHUNK_BYTES);
    }
    while ((msg[0] & 1) == 0);

    return NULL;
}
