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

#include "AFU.h"
#include "awb/provides/qa_device.h"


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

    printf("Writing DSM base %llx ...\n", dsmBuffer->physicalAddress);

    // write physical address of DSM to AFU CSR
    WriteCSR64(CSR_AFU_DSM_BASE, dsmBuffer->physicalAddress);

    printf("Waiting for DSM update...\n");

    // poll AFU_ID until it is non-zero

    while (ReadDSM(0) == 0)
    {
        printf("Polling DSM...\n"); sleep(1);
    }

    cout << "AFU ready." << endl;
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
AFU_CLASS::CreateSharedBuffer(uint64_t size_bytes) {
    AFU_BUFFER buffer = afuClient->CreateSharedBuffer(size_bytes);

    // store buffer in vector, so it can be released later
    buffers.push_back(buffer);

    // return buffer struct
    return buffer;
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
AFU_CLIENT_CLASS::CreateSharedBuffer(uint64_t size_bytes)
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
    memset((void *)buffer->virtualAddress, 0, size_bytes);

    return buffer;
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
    ASSERT(NULL != m_pAALService);

    // CCIAFU Service publishes ICCIAFU as subclass interface.
    m_Service = subclass_ptr<ICCIAFU>(pServiceBase);
    ASSERT(NULL != m_Service);

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
