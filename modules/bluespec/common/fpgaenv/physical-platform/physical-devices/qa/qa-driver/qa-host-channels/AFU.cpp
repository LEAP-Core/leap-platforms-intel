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

#include <iostream>
#include <string>
#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>

#include "AFU.h"

AFU::AFU(const uint32_t* expected_afu_id,
         CCIDeviceImplementation imp,
         uint32_t dsm_size_bytes)
{
    // create the CCI device factory and device
    pCCIDevFactory = GetCCIDeviceFactory(imp);
    pCCIDevice = pCCIDevFactory->CreateCCIDevice();

    // create buffer for DSM
    dsmBuffer = CreateSharedBuffer(dsm_size_bytes);

    // reset AFU
    ResetAFU();

    printf("Writing DSM base %llx ...\n", dsmBuffer->physicalAddress);

    // write physical address of DSM to AFU CSR
    WriteCSR64(CSR_AFU_DSM_BASE, dsmBuffer->physicalAddress);

    printf("Waiting for DSM update...\n");

    // poll AFU_ID until it is non-zero

    while (ReadDSM(0) == 0)
    {
        printf("Polling DSM...\n"); sleep(1);
    }

    // check AFU_ID against expected value
    for (int i = 0; i < 4; i++)
    {
        uint32_t afu_id = ReadDSM(4*i);
        if (afu_id != expected_afu_id[i])
        {
            printf("ERROR: AFU_ID[%d] = 0x%x, expected 0x%x\n", i, afu_id, expected_afu_id[i]);
            exit(1);
        }
    }

    cout << "Found expected AFU ID. AFU ready.\n";
}


AFU::~AFU() {
    // release all workspace buffers
    for (int i = 0; i < buffers.size(); i++)
    {
        pCCIDevice->FreeWorkspace(buffers[i]->workspace);
    }

    // release the CCI device factory and device
    pCCIDevFactory->DestroyCCIDevice(pCCIDevice);
    delete pCCIDevFactory;

    cout << "AFU released\n";
}


AFU_BUFFER 
AFU::CreateSharedBuffer(uint64_t size_bytes) {
    // create a buffer struct instance
    AFU_BUFFER_CLASS* buffer = new AFU_BUFFER_CLASS();

    // create buffer in memory and save info in struct
    buffer->workspace = pCCIDevice->AllocateWorkspace(size_bytes);
    buffer->virtualAddress = buffer->workspace->GetUserVirtualAddress();
    buffer->physicalAddress = buffer->workspace->GetPhysicalAddress();
    buffer->numBytes = buffer->workspace->GetSizeInBytes();

    // store buffer in vector, so it can be released later
    buffers.push_back(buffer);

    // set contents of buffer to 0
    memset((void *)buffer->virtualAddress, 0, size_bytes);

    // return buffer struct
    return buffer;
}


void
AFU::ResetAFU() {
    bt32bitCSR csr;

    const uint32_t CIPUCTL_RESET_BIT = 0x01000000;

    // Assert CAFU Reset
    csr = 0;
    pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
    csr |= CIPUCTL_RESET_BIT;
    pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
  
    // De-assert CAFU Reset
    csr = 0;
    pCCIDevice->GetCSR(CSR_CIPUCTL, &csr);
    csr &= ~CIPUCTL_RESET_BIT;
    pCCIDevice->SetCSR(CSR_CIPUCTL, csr);
}
