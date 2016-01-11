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
#include <assert.h>

#include "awb/provides/qa_device.h"
#include "awb/provides/qa_cci_mpf_shims.h"

#include "awb/provides/physical_platform.h"


AFU AFU_CLASS::instance = NULL;

AFU_CLASS::AFU_CLASS(const char* afuID, uint32_t dsmSizeBytes)
{
    // There should be one global instance of the AFU
    assert(instance == NULL);
    instance = this;

    // Instantiate the accelerator
    afuRuntimeClient = new AFU_RUNTIME_CLIENT_CLASS();
    afuClient = new AFU_CLIENT_CLASS(afuRuntimeClient);
    afuClient->InitService(afuID);

    // create buffer for DSM
    dsmBuffer = CreateSharedBuffer(dsmSizeBytes);

    // reset AFU
    ResetAFU();

    printf("Writing DSM base PA 0x%llx, VA 0x%llx...\n",
           dsmBuffer->physicalAddress,
           dsmBuffer->virtualAddress);

    // write physical address of DSM to AFU CSR
    WriteCSR64(CSR_AFU_DSM_BASE, dsmBuffer->physicalAddress);

    printf("Waiting for DSM update...\n");

    // poll AFU_ID until it is non-zero

    while (ReadDSM64(0) == 0)
    {
        printf("Polling DSM...\n"); sleep(1);
    }

    //
    // Compare the DSM response to CCI-P CSRs
    //
    for (int i = 0; i <= 32; i += 8)
    {
        printf("CSR%d: 0x%016llx\n", i, ReadCSR64(i));
    }

    // Allocate the virtual to physical translation table that enables
    // host/FPGA shared virtual regions.  Shared regions are allocated
    // with the CreateSharedBufferInVM() method.
    vtp = new CCI_MPF_SHIM_VTP_CLASS(afuClient);

    printf("AFU Ready (0x%016llx)\n", ReadDSM64(0));
}


AFU_CLASS::~AFU_CLASS() {
    // release all workspace buffers
    for (int i = 0; i < buffers.size(); i++)
    {
        afuClient->FreeSharedBuffer(buffers[i]);
    }

    // release the CCI device factory and device
    afuClient->UninitService();
    delete afuClient;
    delete afuRuntimeClient;

    cout << "AFU released\n";
}


AFU_BUFFER 
AFU_CLASS::CreateSharedBuffer(size_t size_bytes) {
    AFU_BUFFER buffer = afuClient->CreateSharedBuffer(size_bytes);

    // store buffer in vector, so it can be released later
    buffers.push_back(buffer);

    // return buffer struct
    return buffer;
}


void*
AFU_CLASS::CreateSharedBufferInVM(size_t size_bytes)
{
    return vtp->CreateSharedBufferInVM(size_bytes);
}


btPhysAddr
AFU_CLASS::SharedBufferVAtoPA(const void* va)
{
    return vtp->SharedBufferVAtoPA(va);
}


void
AFU_CLASS::ResetAFU()
{
    btCSRValue csr;

    const uint32_t CIPUCTL_RESET_BIT = 0x01000000;

    // Assert CAFU Reset
    csr = 0;
    afuClient->ReadCSR(CSR_CIPUCTL, &csr);
    csr |= CIPUCTL_RESET_BIT;
    WriteCSR(CSR_CIPUCTL, csr);
  
    // De-assert CAFU Reset
    csr = 0;
    afuClient->ReadCSR(CSR_CIPUCTL, &csr);
    csr &= ~CIPUCTL_RESET_BIT;
    WriteCSR(CSR_CIPUCTL, csr);
}


bool
AFU_CLASS::WriteCSR(btCSROffset offset, bt32bitCSR value)
{
    return afuClient->WriteCSR(offset, value);
}


bool
AFU_CLASS::WriteCSR64(btCSROffset offset, bt64bitCSR value)
{
    return afuClient->WriteCSR64(offset, value);
}


//
// CCI-S compatibility mode function: read a CSR from the hardware.
// MMIO reads are mapped to writes by the hardware to the DSM, line 1.
//
uint64_t
AFU_CLASS::ReadCSR64(uint32_t n)
{
    // The FPGA will write to CTRL line 1.  Clear it first.
    memset((void*)DSMAddress(CL(1)), 0, CL(1));

    // Write CSR to trigger a register read
    WriteCSR(CSR_AFU_MMIO_READ_COMPAT, n >> 2);

    // Wait for the response, signalled by bit 64 in the line being set.
    while (ReadDSM64(CL(1) + sizeof(uint64_t)) == 0) {};

    return ReadDSM64(CL(1));
}


//
// Read from status register space.  Status registers are implemented in
// the FPGA side of this driver and are intended for debugging.
//
uint64_t
AFU_CLASS::ReadSREG64(uint32_t n)
{
    // The FPGA will write to CTRL line 1.  Clear it first.
    memset((void*)DSMAddress(CL(1)), 0, CL(1));

    // Write CSR to trigger a register read
    WriteCSR(CSR_AFU_SREG_READ, n);

    // Wait for the response, signalled by bit 64 in the line being set.
    while (ReadDSM64(CL(1) + sizeof(uint64_t)) == 0) {};

    return ReadDSM64(CL(1));
}


void
AFU_CLASS::RunTests(QA_HOST_CHANNELS_DEVICE qa)
{
#if (QA_PLATFORM_MEMTEST != 0)
    void* base = CreateSharedBufferInVM(MB(64));
    // Send base PA
    uint64_t base_line = uint64_t(base) >> 6;
    uint64_t pa_line = SharedBufferVAtoPA(base) >> 6;
    printf("Host VA: 0x%p, VA line: 0x%016llx\n", base, base_line);
    printf("Host PA: 0x%016llx, PA line: 0x%016llx\n", SharedBufferVAtoPA(base), pa_line);

    // Send 30 bits at a time, high part first.  Low 2 bits must be 0 and
    // aren't part of the address.
    ReadSREG64(uint32_t((base_line >> 30) << 2));
    ReadSREG64(uint32_t(base_line << 2));

    uint32_t cached = 4;
    uint32_t check_order = 8;
    uint32_t trips = 0x3ffff00 | cached | check_order;
//    trips = 8192 | cached | check_order;
    uint64_t cycles;
    uint64_t rdWrCnt;
    uint64_t totalActiveRd;

    printf("Trips %d, %scached, %sordered\n",
           trips & ~3,
           trips & 4 ? "" : "not ",
           trips & 8 ? "" : "not ");

    double gb;
    double sec;

    cycles = ReadSREG64(trips | 1);
    rdWrCnt = ReadSREG64(0);
    totalActiveRd = ReadSREG64(0);
    gb = 64.0 * double(rdWrCnt >> 32) / (1024.0 * 1024.0 * 1024.0);
    sec = 5.0 * double(cycles) * 1.0e-9;
    printf("Read %ld in %lld cycles (%0.4f GB/s), latency %lld cycles (%d ns)\n",
           rdWrCnt >> 32, cycles,
           gb / sec,
           totalActiveRd / cycles, 5 * totalActiveRd / cycles);

    *(uint64_t*)base = 0xdeadbeef;
    cycles = ReadSREG64(trips | 2);
    rdWrCnt = ReadSREG64(0);
    totalActiveRd = ReadSREG64(0);
    gb = 64.0 * double(rdWrCnt & 0xffffffff) / (1024.0 * 1024.0 * 1024.0);
    sec = 5.0 * double(cycles) * 1.0e-9;
    printf("Write %ld in %lld cycles (%0.4f GB/s)\n",
           rdWrCnt & 0xffffffff, cycles,
           gb / sec);

    *(uint64_t*)base = 0xdeadbeef;
    cycles = ReadSREG64(trips | 2);
    rdWrCnt = ReadSREG64(0);
    totalActiveRd = ReadSREG64(0);
    gb = 64.0 * double(rdWrCnt & 0xffffffff) / (1024.0 * 1024.0 * 1024.0);
    sec = 5.0 * double(cycles) * 1.0e-9;
    printf("Write %ld in %lld cycles (%0.4f GB/s)\n",
           rdWrCnt & 0xffffffff, cycles,
           gb / sec);

    cycles = ReadSREG64(trips | 3);
    rdWrCnt = ReadSREG64(0);
    totalActiveRd = ReadSREG64(0);
    gb = 64.0 * (double(rdWrCnt >> 32) + double(rdWrCnt & 0xffffffff)) / (1024.0 * 1024.0 * 1024.0);
    sec = 5.0 * double(cycles) * 1.0e-9;
    printf("Read %ld in %lld cycles\n",
           rdWrCnt >> 32, cycles);
    printf("Write %ld in %lld cycles\n",
           rdWrCnt & 0xffffffff, cycles);
    printf("Total throughput %0.4f GB/s)\n", gb / sec);
#endif
}


// ========================================================================
//
//   AFU_CLIENT_CLASS implementation.
//
// ========================================================================

AFU_CLIENT_CLASS::AFU_CLIENT_CLASS(AFU_RUNTIME_CLIENT rtc) :
    m_pAALService(NULL),
    m_runtimeClient(rtc),
    m_Service(NULL),
    m_Result(0),
    m_WrkVA(NULL),
    m_WrkPA(0),
    m_WrkBytes(0)
{
    SetSubClassInterface(iidServiceClient, dynamic_cast<IServiceClient *>(this));
    SetInterface(iidCCIClient, dynamic_cast<ICCIClient *>(this));

    m_Sem.Create(0, 1);
    m_SemWrk.Create(0, 1);
}

AFU_CLIENT_CLASS::~AFU_CLIENT_CLASS()
{
    m_Sem.Destroy();
    m_SemWrk.Destroy();
}

btInt
AFU_CLIENT_CLASS::InitService(const char* afuID)
{
    // Request our AFU.
    //
    // NOTE: This code bypasses the resource manager's configuration record
    // lookup mechanism.
    NamedValueSet manifest;
    NamedValueSet config_record;

#if (CCI_SIMULATION == 0)
    // Use FPGA hardware
    config_record.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libHWCCIAFU");
    config_record.Add(keyRegAFU_ID, afuID);
    config_record.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_AIA_NAME, "libAASUAIA");
#else
    // Use ASE based RTL simulation
    config_record.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libASECCIAFU");
    config_record.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE, true);
#endif

    manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, config_record);
    manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "LEAP Runtime");

    // Allocate the Service and allocate the required workspace.
    //   This happens in the background via callbacks (simple state machine).
    //   When everything is set we do the real work here in the main thread.
   m_runtimeClient->getRuntime()->allocService(dynamic_cast<IBase *>(this),
                                               manifest);
   m_Sem.Wait();

   return m_Result;
}


btInt
AFU_CLIENT_CLASS::UninitService()
{
    (dynamic_ptr<IAALService>(iidService, m_pAALService))->Release(TransactionID());
    m_Sem.Wait();

    m_runtimeClient->end();
}


AFU_BUFFER
AFU_CLIENT_CLASS::CreateSharedBuffer(size_t size_bytes)
{
    //
    // The API doesn't return the workspace.  Instead, a callback is informed
    // about the details.
    //
    // The lock is needed because the callback records state returned by
    // the method here.
    //
    AutoLock(m_Service);

    m_Service->WorkspaceAllocate(size_bytes, TransactionID(0));
    m_SemWrk.Wait();

    // Create an AFU_BUFFER descriptor with the workspace details.
    AFU_BUFFER_CLASS* buffer = new AFU_BUFFER_CLASS();

    buffer->virtualAddress = m_WrkVA;
    buffer->physicalAddress = m_WrkPA;
    buffer->numBytes = m_WrkBytes;

    // set contents of buffer to 0
    if (buffer->virtualAddress != NULL)
    {
        memset((void *)buffer->virtualAddress, 0, size_bytes);
        return buffer;
    }

    // Failed
    delete buffer;
    return NULL;
}


void
AFU_CLIENT_CLASS::FreeSharedBuffer(AFU_BUFFER buffer)
{
    m_Service->WorkspaceFree(btVirtAddr(buffer->virtualAddress),
                             TransactionID(0));
}


// We must implement the IServiceClient interface (IServiceClient.h):

// <begin IServiceClient interface>
void
AFU_CLIENT_CLASS::serviceAllocated(
    IBase *pServiceBase,
    TransactionID const &rTranID)
{
    m_pAALService = pServiceBase;
    assert(NULL != m_pAALService);

    // CCIAFU Service publishes ICCIAFU as subclass interface.
    m_Service = subclass_ptr<ICCIAFU>(pServiceBase);
    assert(NULL != m_Service);

    m_Sem.Post(1);
}


void
AFU_CLIENT_CLASS::serviceAllocateFailed(const IEvent &rEvent)
{
    IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
    fprintf(stderr, "ERROR: AFU CLIENT service allocation failed: %s\n",
            pExEvent->Description());

    // Remember the error
    ++m_Result;

    m_Sem.Post(1);
}


void
AFU_CLIENT_CLASS::serviceFreed(TransactionID const &rTranID)
{
    m_Sem.Post(1);
}


// <ICCIClient>
void
AFU_CLIENT_CLASS::OnWorkspaceAllocated(TransactionID const &TranID,
                                       btVirtAddr           WkspcVirt,
                                       btPhysAddr           WkspcPhys,
                                       btWSSize             WkspcSize)
{
    m_WrkVA = WkspcVirt;
    m_WrkPA = WkspcPhys;
    m_WrkBytes = WkspcSize;

    m_SemWrk.Post(1);
}


void
AFU_CLIENT_CLASS::OnWorkspaceAllocateFailed(const IEvent &rEvent)
{
    IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
    fprintf(stderr, "ERROR: AFU CLIENT workspace allocation failed: %s\n",
            pExEvent->Description());

    m_WrkVA = NULL;
    m_WrkPA = 0;
    m_WrkBytes = 0;
    m_SemWrk.Post(1);
}


void
AFU_CLIENT_CLASS::OnWorkspaceFreed(TransactionID const &TranID)
{
}

void AFU_CLIENT_CLASS::OnWorkspaceFreeFailed(const IEvent &rEvent)
{
    IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);
    fprintf(stderr, "ERROR: AFU CLIENT workspace free failed: %s\n",
            pExEvent->Description());
}


void AFU_CLIENT_CLASS::serviceEvent(const IEvent &rEvent)
{
    fprintf(stderr, "ERROR: AFU CLIENT unexpected event 0x%lx\n", rEvent.SubClassID());
}


// ========================================================================
//
//   AFU_RUNTIME_CLIENT_CLASS implementation.
//
// ========================================================================

AFU_RUNTIME_CLIENT_CLASS::AFU_RUNTIME_CLIENT_CLASS() :
    m_Runtime(),
    m_pRuntime(NULL),
    m_isActive(false)
{
    NamedValueSet configArgs;
    NamedValueSet configRecord;

    // Publish our interface
    SetSubClassInterface(iidRuntimeClient, dynamic_cast<IRuntimeClient *>(this));

    m_Sem.Create(0, 1);

    // Using Hardware Services requires the Remote Resource Manager Broker
    // Service.  Note that this could also be accomplished by setting the
    // environment variable XLRUNTIME_CONFIG_BROKER_SERVICE to librrmbroker.
#if (CCI_SIMULATION == 0)
    configRecord.Add(XLRUNTIME_CONFIG_BROKER_SERVICE, "librrmbroker");
    configArgs.Add(XLRUNTIME_CONFIG_RECORD,configRecord);
#endif

    if (!m_Runtime.start(this, configArgs))
    {
        m_isActive = false;

        fprintf(stderr, "ERROR: AFU runtime failed to start");
        exit(1);
    }

    // Wait for confirmation that all callbacks fired.
    m_Sem.Wait();
}


AFU_RUNTIME_CLIENT_CLASS::~AFU_RUNTIME_CLIENT_CLASS()
{
    m_Sem.Destroy();
}


void
AFU_RUNTIME_CLIENT_CLASS::end()
{
    m_Runtime.stop();
    m_Sem.Wait();
}


//
// Callbacks...
//

void
AFU_RUNTIME_CLIENT_CLASS::runtimeStarted(
    IRuntime *pRuntime,
    const NamedValueSet &rConfigParms)
{
    // Save a copy of our runtime interface instance.
    m_pRuntime = pRuntime;
    m_isActive = true;

    // Note callback was called
    m_Sem.Post(1);
}

void
AFU_RUNTIME_CLIENT_CLASS::runtimeStopped(IRuntime *pRuntime)
{
    m_isActive = false;

    // Note callback was called
    m_Sem.Post(1);
}

void
AFU_RUNTIME_CLIENT_CLASS::runtimeStartFailed(const IEvent &rEvent)
{
   IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);

   fprintf(stderr, "ERROR: AFU runtime start failed: %s\n",
           pExEvent->Description());
}

void
AFU_RUNTIME_CLIENT_CLASS::runtimeAllocateServiceFailed( IEvent const &rEvent)
{
   IExceptionTransactionEvent * pExEvent = dynamic_ptr<IExceptionTransactionEvent>(iidExTranEvent, rEvent);

   fprintf(stderr, "ERROR: AFU runtime allocation failed: %s\n",
           pExEvent->Description());
}

void
AFU_RUNTIME_CLIENT_CLASS::runtimeAllocateServiceSucceeded(
    IBase *pClient,
    TransactionID const &rTranID)
{
}

void AFU_RUNTIME_CLIENT_CLASS::runtimeEvent(const IEvent &rEvent)
{
}
