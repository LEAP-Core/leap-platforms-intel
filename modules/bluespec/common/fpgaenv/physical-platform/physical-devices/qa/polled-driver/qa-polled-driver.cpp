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
    unsigned char* buf,
    int bytes_requested)
{
    while(!initReadComplete) 
    {
        sleep(1);
    }

    int chunkNumber = 0, bytesRead = 0;
    UMF_CHUNK controlChunk = 0;

    // I really only want to deal in chunks for now.
    assert(bytes_requested % UMF_CHUNK_BYTES == 0);

    if (QA_DRIVER_DEBUG)
    {
        printf("READ needs %d bytes\n", bytes_requested);
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

    for(;  (bytesRead < bytes_requested) && (readChunkNumber < readChunksTotal); bytesRead += UMF_CHUNK_BYTES)
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
        if(bytesRead < bytes_requested)
        {
            if (QA_DRIVER_DEBUG)
            {
                printf("Tail recurse for read needed\n");
            }

            Read(buf+bytesRead, bytes_requested - bytesRead);
        }
    }
}

// write
void
QA_DEVICE_CLASS::Write(
    unsigned char* buf,
    int bytes_requested)
{
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
   
    assert(bytes_requested < FRAME_CHUNKS * UMF_CHUNK_BYTES);

    // Spin for next frame.
    do
    {
        controlChunk = *controlAddr;
        if (QA_DRIVER_DEBUG)
        {
            printf("WRITE: Control chunk %p is %llx \n", controlAddr, controlChunk);
        }
    } while(controlChunk & 0x1);


    for(int offset = 0;  offset < bytes_requested; offset += UMF_CHUNK_BYTES)
    {
        chunkNumber++;
        volatile UMF_CHUNK *chunkAddr = getChunkAddress(writeBuffer, writeFrameNumber, chunkNumber);
        *chunkAddr = *((UMF_CHUNK *)(buf+offset));
        if (QA_DRIVER_DEBUG)
        {
            printf("WRITE writing chunk address %p %llx %llx\n", chunkAddr, *chunkAddr, *((UMF_CHUNK *)(buf+offset))); 
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



