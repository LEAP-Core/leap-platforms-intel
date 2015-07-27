//
// Copyright (c) 2015, Intel Corporation
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

#ifndef AFU_H
#define AFU_H

#include <time.h>
#include <vector>
#include <aalsdk/ccilib/CCILib.h>
#include <aalsdk/aalclp/aalclp.h>
#include "AFU_csr.h"

USING_NAMESPACE(std)
USING_NAMESPACE(CCILib)

//
// Descriptor for a shared memory buffer
//
typedef struct
{
    ICCIWorkspace    *workspace;
    volatile uint8_t *virtualAddress;
    btPhysAddr        physicalAddress;
    uint64_t          numBytes;
}
AFU_BUFFER_CLASS;

// Fields describing a typical AFU buffer may not be modified after allocation.
typedef const AFU_BUFFER_CLASS *AFU_BUFFER;

typedef class AFU_CLASS *AFU;

class AFU_CLASS
{
  private:
    static AFU instance;

  public:
    // CCI_AAL     = AAL AFU implementation.
    // CCI_ASE     = AFU Simulation Environment implementation.
    // CCI_DIRECT  = Direct CCI driver implementation.

    AFU_CLASS(const uint32_t *expected_afu_id,
              CCIDeviceImplementation imp = CCI_ASE,
              uint32_t dsm_size_bytes = 4096);

    ~AFU_CLASS();

    // There is a single instance of the AFU allocated.  This allows any
    // code to find it.
    static AFU GetInstance() { return instance; }

    void ResetAFU();

    //
    // Allocate a memory buffer shared by the host and an FPGA
    //
    AFU_BUFFER CreateSharedBuffer(uint64_t size_bytes);

    //
    // DSM is a relatively small shared memory buffer defined by the CCI
    // specification for communicating basic state between units.  Initial
    // handshaking between an FPGA and the host begins with messages
    // passed through the buffer.
    //
    inline volatile void *DSMAddress(uint32_t offset) {
        return (void *)(dsmBuffer->virtualAddress + offset);
    }

    inline volatile uint32_t ReadDSM(uint32_t offset) {
        return *(volatile uint32_t *)(dsmBuffer->virtualAddress + offset);
    }

    inline volatile uint64_t ReadDSM64(uint32_t offset) {
        return *(volatile uint64_t *)(dsmBuffer->virtualAddress + offset);
    }

    //
    // CSRs for sending commands to an FPGA.  Because of QPI/KTI bus timing
    // there is no corresponding CSR read.  Messages from FPGA to host are
    // usually passed in the DSM buffer.
    //
    inline bool WriteCSR(btCSROffset offset, bt32bitCSR value) {
        return pCCIDevice->SetCSR(offset, value);
    }

    inline bool WriteCSR64(btCSROffset offset, bt64bitCSR value) {
        bool result = pCCIDevice->SetCSR(offset + 4, value >> 32);
        result |= pCCIDevice->SetCSR(offset, value & 0xffffffff);
        return result;
    }

  private:
    ICCIDeviceFactory *pCCIDevFactory;
    ICCIDevice *pCCIDevice;
    std::vector<AFU_BUFFER> buffers;
    AFU_BUFFER dsmBuffer;
};

#endif
