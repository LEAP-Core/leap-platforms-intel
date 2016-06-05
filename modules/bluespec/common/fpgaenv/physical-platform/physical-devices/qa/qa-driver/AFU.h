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

// AAL redefines ASSERT and TRACE
#undef ASSERT
#undef TRACE

#include <time.h>
#include <vector>

#include <aalsdk/AAL.h>

#include "awb/provides/qa_driver.h"
#include "awb/provides/qa_platform_libs.h"

#if (CCI_S_IFC != 0)
#include <aalsdk/xlRuntime.h>
#include <aalsdk/service/ICCIAFU.h>
#include <aalsdk/service/ICCIClient.h>
#include "cci_mpf_csrs.h"
#else
#include <aalsdk/Runtime.h>
#include <aalsdk/service/IALIAFU.h>
#endif

#include "AFU_csr.h"
#include "awb/provides/qa_cci_mpf_sw.h"
#include "awb/restricted/stats-emitter.h"


USING_NAMESPACE(std)
USING_NAMESPACE(AAL)


typedef class AFU_CLIENT_CLASS *AFU_CLIENT;
typedef class AFU_RUNTIME_CLIENT_CLASS *AFU_RUNTIME_CLIENT;
typedef class QA_HOST_CHANNELS_DEVICE_CLASS *QA_HOST_CHANNELS_DEVICE;
typedef class AFU_CCIS_CLASS *AFU_CCIS;


#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MB


//
// Descriptor for a shared memory buffer
//
typedef struct
{
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
    AFU_CLASS(const char* afuID, uint32_t dsmSizeBytes = 4096);
    ~AFU_CLASS();

    // There is a single instance of the AFU allocated.  This allows any
    // code to find it.
    static AFU GetInstance() { return instance; }

    void ResetAFU();

    //
    // Allocate a memory buffer shared by the host and an FPGA.  This call
    // DOES NOT add the VA/PA pair to the FPGA-side VTP.
    //
    AFU_BUFFER CreateSharedBuffer(ssize_t size_bytes);

    //
    // Allocate a shared memory buffer and add the VA/PA mapping to the
    // FPGA-side VTP from the MPF (Memory Properties Factor) library.
    //
    void* CreateSharedBufferInVM(ssize_t size_bytes);

    // Virtual to physical translation for memory created by
    // CreateSharedBufferInVM.
    btPhysAddr SharedBufferVAtoPA(const void* va);


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
    bool WriteCSR(btCSROffset offset, bt32bitCSR value);
    bool WriteCSR64(btCSROffset offset, bt64bitCSR value);

    //
    // Read CSR from the hardware.
    //
    uint64_t ReadCSR64(uint32_t n);
    bool ReadCSR64(btCSROffset offset, bt64bitCSR* pValue);

    // The driver implements a status register space in the FPGA.
    // The protocol is very slow -- the registers are intended for debugging.
    uint64_t ReadSREG64(uint32_t n);


    void RunTests(QA_HOST_CHANNELS_DEVICE qa);


    //
    // Properties of the system.
    //
    const uint64_t ByteAddrToLineIdx(uint64_t addr) { return addr / CL(1); }
    const uint64_t ByteAddrToLineIdx(const void* addr) { return uint64_t(addr) / CL(1); }

  private:
    AFU_RUNTIME_CLIENT afuRuntimeClient;
    AFU_CLIENT afuClient;

    std::vector<AFU_BUFFER> buffers;
    AFU_BUFFER dsmBuffer;
};


//
// AFU_CLIENT_CLASS --
//   Define our client class so that we can receive notifications from the
//   AAL Runtime.
//
class AFU_CLIENT_CLASS: public CAASBase,
#if (CCI_S_IFC != 0)
                        public ICCIClient,
#endif
                        public IServiceClient,
                        public STATS_EMITTER_CLASS
{
public:
    AFU_CLIENT_CLASS(AFU afu, AFU_RUNTIME_CLIENT rtc);
    ~AFU_CLIENT_CLASS();

    btInt InitService(const char* afuID);
    btInt UninitService();

    inline bool WriteCSR(btCSROffset offset, bt32bitCSR value)
    {
#if (CCI_S_IFC != 0)
        return m_Service->CSRWrite(offset, value);
#else
        return m_pALIMMIOService->mmioWrite32(offset, value);
#endif
    }

    inline bool WriteCSR64(btCSROffset offset, bt64bitCSR value)
    {
#if (CCI_S_IFC != 0)
        return m_Service->CSRWrite64(offset, value);
#else
        return m_pALIMMIOService->mmioWrite64(offset, value);
#endif
    }

    inline bool ReadCSR(btCSROffset offset, bt32bitCSR* pValue)
    {
#if (CCI_S_IFC != 0)
        btCSRValue v;
        bool r = m_Service->CSRRead(offset, &v);
        *pValue = v;
        return r;
#else
        return m_pALIMMIOService->mmioRead32(offset, pValue);
#endif
    }

    inline bool ReadCSR64(btCSROffset offset, bt64bitCSR* pValue)
    {
#if (CCI_S_IFC != 0)
        return false;
#else
        return m_pALIMMIOService->mmioRead64(offset, pValue);
#endif
    }

    void ResetAFU();

    //
    // Allocate a memory buffer shared by the host and an FPGA.
    //
    AFU_BUFFER CreateSharedBuffer(ssize_t size_bytes);
    void FreeSharedBuffer(AFU_BUFFER buffer);

    void* CreateSharedBufferInVM(ssize_t size_bytes);
    btPhysAddr SharedBufferVAtoPA(const void* va);

    // <begin IServiceClient interface>
    void serviceAllocated(IBase *pServiceBase,
                          TransactionID const &rTranID);
    void serviceAllocateFailed(const IEvent &rEvent);
    void serviceReleased(const TransactionID &rTranID);
    void serviceReleaseFailed(const IEvent &rEvent);

    // CCI-S only
    void serviceFreed(TransactionID const &rTranID);

    void serviceEvent(const IEvent &rEvent);
    // <end IServiceClient interface>

#if (CCI_S_IFC != 0)
    // <ICCIClient> -- used only by CCI-S
    virtual void OnWorkspaceAllocated(TransactionID const &TranID,
                                      btVirtAddr WkspcVirt,
                                      btPhysAddr WkspcPhys,
                                      btWSSize WkspcSize);
    virtual void OnWorkspaceAllocateFailed(const IEvent &Event);
    virtual void OnWorkspaceFreed(TransactionID const &TranID);
    virtual void OnWorkspaceFreeFailed(const IEvent &Event);
#endif
    // </ICCIClient>

    // STATS_EMITTER_CLASS virtual functions
    void EmitStats(ofstream &statsFile);
    void ResetStats();

  private:
    uint64_t GetStatVTP(t_cci_mpf_vtp_csr_offsets stat);

  protected:
    AFU            afu;
    IBase         *m_pAALService;    // The generic AAL Service interface for the AFU.

#if (CCI_S_IFC != 0)
    ICCIAFU       *m_Service;

    // CCI-S compatibility layer.  The CCI-S version of the memory allocator
    // used by VTP is here.  In CCI-P the ability to allocate large blocks
    // of shared virtual memory became part of the standard release.
    AFU_CCIS       afu_ccis_compat;
#else
    IALIBuffer    *m_pALIBufferService; ///< Pointer to Buffer Service
    IALIMMIO      *m_pALIMMIOService;   ///< Pointer to MMIO Service
    IALIReset     *m_pALIResetService;  ///< Pointer to AFU Reset Service

    // Shared translation and virtual memory manager.
    MPFVTP        *m_mpf_vtp;
    btCSROffset    m_VTPDFHOffset;      ///< VTP DFH offset

    // Virtual channel mapping
    MPFVCMAP      *m_mpf_vc_map;
    btCSROffset    m_VCMAPDFHOffset;    ///< VC MAP DFH offset
#endif
    AFU_RUNTIME_CLIENT m_runtimeClient;
    CSemaphore     m_Sem;            // For synchronizing with the AAL runtime.
    CSemaphore     m_SemWrk;         // Semaphore for workspace syc
    btInt          m_Result;         // Returned result value; 0 if success

    // Workspace info
    btVirtAddr     m_WrkVA;          // Most recent workspace alloc VA
    btPhysAddr     m_WrkPA;          // Most recent workspace alloc PA
    btWSSize       m_WrkBytes;       // Most recent workspace alloc size
};


//
// AFU_RUNTIME_CLIENT_CLASS --
//   Define our runtime client class so that we can receive the runtime
//   started/stopped notifications.
//
class AFU_RUNTIME_CLIENT_CLASS : public CAASBase,
                                 public IRuntimeClient
{
public:
    AFU_RUNTIME_CLIENT_CLASS();
    ~AFU_RUNTIME_CLIENT_CLASS();

    void end();
    IRuntime* getRuntime() const { return m_pRuntime; };
    btBool isActive() const { return m_isActive; };

    // <begin IRuntimeClient interface>
    void runtimeStarted(IRuntime *pRuntime,
                        const NamedValueSet &rConfigParms);
    void runtimeStopped(IRuntime *pRuntime);
    void runtimeStartFailed(const IEvent &rEvent);
    void runtimeStopFailed(const IEvent &rEvent);
    void runtimeAllocateServiceFailed(IEvent const &rEvent);
    void runtimeAllocateServiceSucceeded(IBase *pClient,
                                         TransactionID const &rTranID);
    void runtimeEvent(const IEvent &rEvent);

    // Not Used
    void runtimeCreateOrGetProxyFailed(IEvent const &rEvent) {};

    // <end IRuntimeClient interface>

  protected:
    IRuntime   *m_pRuntime;  // Pointer to AAL runtime instance.
    Runtime     m_Runtime;   // AAL Runtime
    btBool      m_isActive;  // Status
    CSemaphore  m_Sem;       // For synchronizing with the AAL runtime.
};


#endif
