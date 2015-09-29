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

#ifndef __QA_SOFTWARE_DRIVER__
#define __QA_SOFTWARE_DRIVER__

#include "awb/provides/command_switches.h"
#include "awb/provides/umf.h"

#include "tbb/atomic.h"

// AAL redefines TRACE
#undef TRACE

// Local includes
#include "AFU.h"

#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB

#define UMF_CHUNKS_PER_CL       (CL(1) / sizeof(UMF_CHUNK))
#define QA_BLOCK_SIZE           UMF_CHUNK_BYTES

//
// DSM offsets for various state.  THESE MUST MATCH THE VALUES IN
// qa_drv_status_manager.sv!
//
typedef enum
{
    DSM_OFFSET_AFU_ID     = CL(0),
    DSM_OFFSET_SREG_RSP   = CL(1),
    DSM_OFFSET_DEBUG_RSP  = CL(2),
    DSM_OFFSET_FIFO_STATE = CL(3),
    DSM_OFFSET_POLL_STATE = CL(4)
}
t_DSM_OFFSETS;


// ==============================================
//          QA Physical Device, software driver
// ==============================================
typedef class QA_DEVICE_CLASS* QA_DEVICE;
class QA_DEVICE_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    // switches for acquiring device uniquifier
    COMMAND_SWITCH_DICTIONARY deviceSwitch;

    // Handles to AFU context.
    AFU_CLASS afu;

    // process/pipe state (physical channel)
    class tbb::atomic<bool> initReadComplete;
    class tbb::atomic<bool> initWriteComplete;

    AFU_BUFFER  readBuffer;
    uint64_t    readBufferBytes;
    uint64_t    readBufferIdxMask;

    // Start/end of the read buffer
    const UMF_CHUNK*  readBufferStart;
    const UMF_CHUNK*  readBufferEnd;    // First address after the buffer

    // Number of chunks remaining in current group
    uint64_t    readChunksAvail;
    // Pointer to next chunk to be read
    const UMF_CHUNK*  readChunksNext;
    // Start of the current read chunk -- used only for debugging
    const UMF_CHUNK*  readChunksCurHead;

    AFU_BUFFER  writeBuffer;
    uint64_t    writeBufferBytes;
    uint64_t    writeBufferIdxMask;
    uint64_t    writeNextLineIdx;
    // Pointer to next chunk to be written
    UMF_CHUNK*  writeChunksNext;

    // Start/end of the write buffer
    UMF_CHUNK*  writeBufferStart;
    UMF_CHUNK*  writeBufferEnd;    // First address after the buffer

  public:
    QA_DEVICE_CLASS(PLATFORMS_MODULE);
    ~QA_DEVICE_CLASS();

    void Init();
    void Cleanup();                            // cleanup
    void Uninit();                             // uninit
    bool Probe();                              // probe for data
    void Read(void* buf, size_t count);        // blocking read
    void Write(const void* buf, size_t count); // write
    void RegisterLogicalDeviceName(string name);

    // The driver implements a status register space in the FPGA.
    // The protocol is very slow -- the registers are intended for debugging.
    uint64_t ReadSREG(uint32_t n);

    // Dump driver state by writing a CSR and waiting for a response in DSM.
    void DebugDump();
    void DebugDumpCurrentReadMessage();
    void DebugDumpReadHistory();

    // Tests
    void TestSend();                    // Test sending to FPGA
    void TestRecv();                    // Test receiving from FPGA
    void TestLoopback();                // Test send and receive

  private:
    //
    // Convert a line offset to an address.
    //
    UMF_CHUNK* getChunkAddressFromOffset(AFU_BUFFER buffer, uint64_t offset)
    {
        // Convert cache line index to byte offset
        offset *= CL(1);

        // Add the base address
        return (UMF_CHUNK*)(buffer->virtualAddress + offset);
    }
};

#endif
