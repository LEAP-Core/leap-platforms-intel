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

#ifndef __QA_WRAPPER__
#define __QA_WRAPPER__

#include "awb/provides/command_switches.h"
#include "awb/provides/umf.h"
#include "awb/provides/qa_driver.h"
#include "awb/provides/qa_driver_host_channels.h"


#define UMF_CHUNKS_PER_CL       (CL(1) / sizeof(UMF_CHUNK))
#define QA_BLOCK_SIZE           UMF_CHUNK_BYTES


class QA_CHAN_TESTS_SWITCH_CLASS : public COMMAND_SWITCH_INT_CLASS
{
  private:
    UINT32 qaChanTests;

  public:
    ~QA_CHAN_TESTS_SWITCH_CLASS() {};
    QA_CHAN_TESTS_SWITCH_CLASS() :
        COMMAND_SWITCH_INT_CLASS("qa-chan-tests"),
        qaChanTests(0)
    {};

    void ProcessSwitchInt(int arg) { qaChanTests = arg; };
    void ShowSwitch(std::ostream& ostr, const string& prefix)
    {
        ostr << prefix << "[--qa-chan-tests=<n>]   Run QA host to FPGA channel tests if non-zero" << endl;
    };

    int Value(void) const { return qaChanTests; }
};


// ========================================================================
//
//   QA device wrapper.  Allocate/initialize the AFU driver.  After
//   initialization most calls are forwarded directly to the driver.
//
// ========================================================================

typedef class QA_DEVICE_WRAPPER_CLASS* QA_DEVICE_WRAPPER;
class QA_DEVICE_WRAPPER_CLASS: public PLATFORMS_MODULE_CLASS
{
  private:
    // switches for acquiring device uniquifier
    COMMAND_SWITCH_DICTIONARY deviceSwitch;
    QA_CHAN_TESTS_SWITCH_CLASS testSwitch;

    // Handles to AFU context.
    AFU_CLASS afu;

    // FIFO channels to/from FPGA
    QA_HOST_CHANNELS_DEVICE_CLASS channelDev;

    // Number of bytes remaining in current packet
    size_t bytesLeftInPacket;

    UMF_CHUNK nextReadHeader;

  public:
    QA_DEVICE_WRAPPER_CLASS(PLATFORMS_MODULE);
    ~QA_DEVICE_WRAPPER_CLASS();

    void Init();
    void Cleanup();                             // cleanup
    void Uninit();                              // uninit

    bool Probe();                               // probe for data
    size_t Read(void* buf, size_t nBytes, bool block = true);

    inline void Write(const void* buf, size_t nBytes); // write
    inline void Flush();                        // Complete pending writes

    void RegisterLogicalDeviceName(string name);

    // The driver implements a status register space in the FPGA.
    // The protocol is very slow -- the registers are intended for debugging.
    inline uint64_t ReadSREG64(uint32_t n);
};



inline bool
QA_DEVICE_WRAPPER_CLASS::Probe()
{
    return channelDev.Probe();
}


inline size_t
QA_DEVICE_WRAPPER_CLASS::Read(
    void* buf,
    size_t nBytes,
    bool block)
{
    return channelDev.Read(buf, nBytes, block);
}


//
// Write a message to the FPGA.
//
inline void
QA_DEVICE_WRAPPER_CLASS::Write(
    const void* buf,
    size_t nBytes)
{
    // nBytes must be a multiple of the UMF_CHUNK size
    assert((nBytes & (UMF_CHUNK_BYTES-1)) == 0);

    channelDev.Write(buf, nBytes);
}


//
// Complete pending writes.  Writes are forwarded as multiples of the FPGA cache
// line size.  Partial writes are padded with 0's.
//
inline void
QA_DEVICE_WRAPPER_CLASS::Flush()
{
    channelDev.Flush();
}


//
// Read from status register space.  Status registers are implemented in
// the FPGA side of this driver and are intended for debugging.
//
inline uint64_t
QA_DEVICE_WRAPPER_CLASS::ReadSREG64(uint32_t n)
{
    return afu.ReadSREG64(n);
}
#endif
