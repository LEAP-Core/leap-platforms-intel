//
// Copyright (c) 2016, Intel Corporation
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

#ifndef __AAL_SVC_WRAPPER_H__
#define __AAL_SVC_WRAPPER_H__ 1

#include <aalsdk/AALTypes.h>
#include <aalsdk/Runtime.h>
#include <aalsdk/AALLoggerExtern.h>

#include <aalsdk/service/IALIAFU.h>
#include "IMPF.h"

#include <string.h>

using namespace std;
using namespace AAL;


//
// Convenience macros for printing messages and errors.
//
#ifdef MSG
# undef MSG
#endif // MSG
#define MSG(x) std::cout << __AAL_SHORT_FILE__ << ':' << __LINE__ << ':' << __AAL_FUNC__ << "() : " << x << std::endl
#ifdef ERR
# undef ERR
#endif // ERR
#define ERR(x) std::cerr << __AAL_SHORT_FILE__ << ':' << __LINE__ << ':' << __AAL_FUNC__ << "() **Error : " << x << std::endl



class AAL_SVC_WRAPPER: public CAASBase,
                       public IRuntimeClient,
                       public IServiceClient
{
  public:
    // Pass true in use_hw to use FPGA or false to use ASE.
    AAL_SVC_WRAPPER(btBool use_hw);
    ~AAL_SVC_WRAPPER();

    btInt initialize();    ///< Return 0 if success
    btInt terminate();    ///< Return 0 if success

    // <begin IServiceClient interface>
    void serviceAllocated(IBase *pServiceBase,
                          TransactionID const &rTranID);

    void serviceAllocateFailed(const IEvent &rEvent);

    void serviceReleased(const AAL::TransactionID&);

    void serviceReleaseRequest(IBase *pServiceBase, const IEvent &rEvent);
    void serviceReleaseFailed(const AAL::IEvent&);

    void serviceEvent(const IEvent &rEvent);
    // <end IServiceClient interface>

    // <begin IRuntimeClient interface>
    void runtimeCreateOrGetProxyFailed(IEvent const &rEvent){};    // Not Used

    void runtimeStarted(IRuntime            *pRuntime,
                        const NamedValueSet &rConfigParms);

    void runtimeStopped(IRuntime *pRuntime);

    void runtimeStartFailed(const IEvent &rEvent);

    void runtimeStopFailed(const IEvent &rEvent);

    void runtimeAllocateServiceFailed( IEvent const &rEvent);

    void runtimeAllocateServiceSucceeded(IBase               *pClient,
                                         TransactionID const &rTranID);

    void runtimeEvent(const IEvent &rEvent);

    btBool isOK()  {return m_bIsOK;}
    // <end IRuntimeClient interface>

  protected:
    btBool         use_hw;
    Runtime        m_Runtime;                ///< AAL Runtime
    IBase         *m_pALIAFU_AALService;     ///< The generic AAL Service interface for the AFU.
    IALIBuffer    *m_pALIBufferService;      ///< Pointer to Buffer Service
  public:
    IALIMMIO      *m_pALIMMIOService;        ///< Pointer to MMIO Service
    IALIReset     *m_pALIResetService;       ///< Pointer to AFU Reset Service
  protected:
    CSemaphore     m_Sem;                    ///< For synchronizing with the AAL runtime.
    btInt          m_Result;                 ///< Returned result value; 0 if success
    TransactionID  m_ALIAFUTranID;           ///< TransactionID used for service allocation

    // MPF service-related information
    IBase         *m_pMPF_AALService;        ///< The generic AAL Service interface for MPF.
    TransactionID  m_MPFTranID;              ///< TransactionID used for service allocation
  public:
    IMPFVTP       *m_pVTPService;            ///< Pointer to VTP buffer service
    IMPFVCMAP     *m_pVCMAPService;          ///< Pointer to VC MAP service
    IMPFWRO       *m_pWROService;            ///< Pointer to WRO service
};

#endif //  __AAL_SVC_WRAPPER_H__
