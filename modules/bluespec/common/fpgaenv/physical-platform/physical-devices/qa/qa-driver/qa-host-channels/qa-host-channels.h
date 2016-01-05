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

#ifndef __QA_HOST_CHANNELS_DRIVER__
#define __QA_HOST_CHANNELS_DRIVER__

#include "awb/provides/command_switches.h"
#include "awb/provides/umf.h"
#include "awb/provides/qa_driver.h"

#include "tbb/atomic.h"


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
typedef class QA_HOST_CHANNELS_DEVICE_CLASS* QA_HOST_CHANNELS_DEVICE;
class QA_HOST_CHANNELS_DEVICE_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    // Handles to AFU context.
    AFU_CLASS& afu;

    // process/pipe state (physical channel)
    class tbb::atomic<bool> initReadComplete;
    class tbb::atomic<bool> initWriteComplete;

    AFU_BUFFER  readBuffer;
    uint64_t    readBufferBytes;

    // Start/end of the read buffer
    const uint8_t*  readBufferStart;
    const uint8_t*  readBufferEnd;    // First address after the buffer

    // Pointer to next address to be filled from FPGA
    const uint8_t*  readFillNext;
    // Pointer to next address to be read
    const uint8_t*  readNext;
    // Number of bytes known to be available for reading, cached from some
    // previous read.
    uint64_t        readBytesAvail;

    AFU_BUFFER  writeBuffer;
    uint64_t    writeBufferBytes;
    uint64_t    writeBufferIdxMask;

    // Start/end of the write buffer
    uint8_t*    writeBufferStart;
    uint8_t*    writeBufferEnd;    // First address after the buffer

    // Pointer to next address to be written
    uint8_t*    writeNext;

    bool        enableTests;

  public:
    QA_HOST_CHANNELS_DEVICE_CLASS(PLATFORMS_MODULE p, AFU_CLASS& afuDev);
    ~QA_HOST_CHANNELS_DEVICE_CLASS();

    void Init();
    void Cleanup();                             // cleanup
    void Uninit();                              // uninit
    bool Probe();                               // probe for data

    // Run tests during Init()
    void EnableTests() { enableTests = true; }

    // Read nBytes from the FPGA.  If block is true then the call blocks
    // until all requested bytes have been received.  If block is false
    // then return whatever data is available.  The returned value is
    // the number of bytes actually read.
    size_t Read(void* buf, size_t nBytes, bool block = true);

    // Write to the channel.  nBytes must be a multiple of a cache line.
    void Write(const void* buf, size_t nBytes);

    // Complete pending writes.  Writes are forwarded as multiples of the
    // FPGA cache line size.  Partial writes are padded with 0's.
    void Flush();

    // The driver implements a status register space in the FPGA.
    // The protocol is very slow -- the registers are intended for debugging.
    uint64_t ReadSREG(uint32_t n);

    // Tests
    void TestSend();                    // Test sending to FPGA
    void TestRecv();                    // Test receiving from FPGA
    void TestLoopback();                // Test send and receive

  private:
    //
    // Convert a line offset to an address.
    //
    inline UMF_CHUNK*
    getChunkAddressFromOffset(AFU_BUFFER buffer, uint64_t offset)
    {
        // Convert cache line index to byte offset
        offset *= CL(1);

        // Add the base address
        return (UMF_CHUNK*)(buffer->virtualAddress + offset);
    }

    //
    // Update pointers following a read.
    //
    inline void UpdateReadPtr(size_t nBytes)
    {
        readBytesAvail -= nBytes;

        // Time to wrap to the beginning?
        readNext += nBytes;
        if (readNext == readBufferEnd)
        {
            readNext = readBufferStart;
        }

        // Update sender credits updating the 2nd uint32_t of DSM POLL_STATE
        // with the index of the line currently being processed.
        uint32_t *cur_read_idx =
            (uint32_t*)afu.DSMAddress(DSM_OFFSET_POLL_STATE +
                                      sizeof(uint32_t));
        *cur_read_idx = (readNext - readBufferStart) / CL(1);
    }
};

#endif
