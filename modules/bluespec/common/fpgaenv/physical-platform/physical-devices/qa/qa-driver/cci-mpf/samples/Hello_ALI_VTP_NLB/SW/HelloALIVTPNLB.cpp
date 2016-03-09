// Copyright(c) 2007-2016, Intel Corporation
//
// Redistribution  and  use  in source  and  binary  forms,  with  or  without
// modification, are permitted provided that the following conditions are met:
//
// * Redistributions of  source code  must retain the  above copyright notice,
//   this list of conditions and the following disclaimer.
// * Redistributions in binary form must reproduce the above copyright notice,
//   this list of conditions and the following disclaimer in the documentation
//   and/or other materials provided with the distribution.
// * Neither the name  of Intel Corporation  nor the names of its contributors
//   may be used to  endorse or promote  products derived  from this  software
//   without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING,  BUT NOT LIMITED TO,  THE
// IMPLIED WARRANTIES OF  MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED.  IN NO EVENT  SHALL THE COPYRIGHT OWNER  OR CONTRIBUTORS BE
// LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,  OR
// CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT LIMITED  TO,  PROCUREMENT  OF
// SUBSTITUTE GOODS OR SERVICES;  LOSS OF USE,  DATA, OR PROFITS;  OR BUSINESS
// INTERRUPTION)  HOWEVER CAUSED  AND ON ANY THEORY  OF LIABILITY,  WHETHER IN
// CONTRACT,  STRICT LIABILITY,  OR TORT  (INCLUDING NEGLIGENCE  OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,  EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//****************************************************************************
/// @file HelloALIVTPNLB.cpp
/// @brief Basic ALI AFU interaction.
/// @ingroup HelloALIVTPNLB
/// @verbatim
/// Intel(R) Accelerator Abstraction Layer Sample Application
///
///    This application is for example purposes only.
///    It is not intended to represent a model for developing commercially-
///       deployable applications.
///    It is designed to show working examples of the AAL programming model and APIs.
///
/// AUTHORS: Joseph Grecco, Intel Corporation
///          Enno Luebbers, Intel Corporation
///
/// This Sample demonstrates how to use the basic ALI APIs including VTP.
///
/// This sample is designed to be used with the xyzALIAFU Service.
///
/// HISTORY:
/// WHEN:          WHO:     WHAT:
/// 12/15/2015     JG       Initial version started based on older sample code.
/// 02/07/2016     EL       Modified for VTP and current NLB.@endverbatim
//****************************************************************************
#include <aalsdk/AALTypes.h>
#include <aalsdk/Runtime.h>
#include <aalsdk/AALLoggerExtern.h>

#include <aalsdk/service/IALIAFU.h>
#include "IMPF.h"

#include <string.h>

//****************************************************************************
// UN-COMMENT appropriate #define in order to enable either Hardware or ASE.
//    DEFAULT is to use Software Simulation.
//****************************************************************************
// #define  HWAFU
#define  ASEAFU

// uncomment to also run negative tests (test the test) - runs a bit longer
#define TEST_NEGATIVE

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

//
// Definitions for test sizes (and associated convenience macros for actually
// calculating those sizes)
#ifndef CL
# define CL(x)                     ((x) * 64)
#endif // CL
#ifndef LOG2_CL
# define LOG2_CL                   6
#endif // LOG2_CL
#ifndef MB
# define MB(x)                     ((x) * 1024 * 1024)
#endif // MBA

#define LPBK1_BUFFER_SIZE        MB(2048)
#define LPBK1_DSM_SIZE           MB(4)

//
// Definitions of NLB CSRs
//
#define CSR_SRC_ADDR             0x0120
#define CSR_DST_ADDR             0x0128
#define CSR_CTL                  0x0138
#define CSR_CFG                  0x0140
#define CSR_NUM_LINES            0x0130
#define DSM_STATUS_TEST_COMPLETE 0x40
#define CSR_AFU_DSM_BASEL        0x0110
#define CSR_AFU_DSM_BASEH        0x0114
#   define NLB_TEST_MODE_PCIE0      0x2000

/// @addtogroup HelloALIVTPNLB
/// @{

/// @brief   Since this is a simple application, our App class implements both the IRuntimeClient and IServiceClient
///           interfaces.  Since some of the methods will be redundant for a single object, they will be ignored.
///
class HelloALIVTPNLBApp: public CAASBase, public IRuntimeClient, public IServiceClient
{
public:

   HelloALIVTPNLBApp();
   ~HelloALIVTPNLBApp();

   btInt run();    ///< Return 0 if success

   // <begin IServiceClient interface>
   void serviceAllocated(IBase *pServiceBase,
                         TransactionID const &rTranID);

   void serviceAllocateFailed(const IEvent &rEvent);

   void serviceReleased(const AAL::TransactionID&);

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
   Runtime        m_Runtime;                ///< AAL Runtime
   IBase         *m_pALIAFU_AALService;     ///< The generic AAL Service interface for the AFU.
   IALIBuffer    *m_pALIBufferService;      ///< Pointer to Buffer Service
   IALIMMIO      *m_pALIMMIOService;        ///< Pointer to MMIO Service
   IALIReset     *m_pALIResetService;       ///< Pointer to AFU Reset Service
   CSemaphore     m_Sem;                    ///< For synchronizing with the AAL runtime.
   btInt          m_Result;                 ///< Returned result value; 0 if success
   TransactionID  m_ALIAFUTranID;           ///< TransactionID used for service allocation

   // VTP service-related information
   IBase         *m_pVTP_AALService;        ///< The generic AAL Service interface for the VTP.
      IMPFVTP       *m_pVTPService;            ///< Pointer to VTP buffer service
   btCSROffset    m_VTPDFHOffset;           ///< VTP DFH offset
   TransactionID  m_VTPTranID;              ///< TransactionID used for service allocation

   // Workspace info
   btVirtAddr     m_pDSM;                   ///< DSM workspace virtual address.
   btWSSize       m_DSMSize;                ///< DSM workspace size in bytes.
   btVirtAddr     m_pInput;                 ///< Input workspace virtual address.
   btWSSize       m_InputSize;              ///< Input workspace size in bytes.
   btVirtAddr     m_pOutput;                ///< Output workspace virtual address.
   btWSSize       m_OutputSize;             ///< Output workspace size in bytes.

private:
   btBool         checkBuffers( btVirtAddr, btVirtAddr, size_t );
                                            ///< Convenience function to check test outcome.
   btBool         runNLB( btVirtAddr, btVirtAddr, size_t, btUnsigned32bitInt );
};

///////////////////////////////////////////////////////////////////////////////
///
///  Implementation
///
///////////////////////////////////////////////////////////////////////////////

/// @brief   Constructor registers this objects client interfaces and starts
///          the AAL Runtime. The member m_bisOK is used to indicate an error.
///
HelloALIVTPNLBApp::HelloALIVTPNLBApp() :
   m_Runtime(this),
   m_pALIAFU_AALService(NULL),
   m_pALIBufferService(NULL),
   m_pALIMMIOService(NULL),
   m_pALIResetService(NULL),
   m_pVTP_AALService(NULL),
   m_pVTPService(NULL),
   m_VTPDFHOffset(-1),
   m_Result(0),
   m_pDSM(NULL),
   m_DSMSize(0),
   m_pInput(NULL),
   m_InputSize(0),
   m_pOutput(NULL),
   m_OutputSize(0),
   m_ALIAFUTranID(),
   m_VTPTranID()
{
   // Register our Client side interfaces so that the Service can acquire them.
   //   SetInterface() is inherited from CAASBase
   SetInterface(iidServiceClient, dynamic_cast<IServiceClient *>(this));
   SetInterface(iidRuntimeClient, dynamic_cast<IRuntimeClient *>(this));

   // Initialize our internal semaphore
   m_Sem.Create(0, 1);

   // Start the AAL Runtime, setting any startup options via a NamedValueSet

   // Using Hardware Services requires the Remote Resource Manager Broker Service
   //  Note that this could also be accomplished by setting the environment variable
   //   AALRUNTIME_CONFIG_BROKER_SERVICE to librrmbroker
   NamedValueSet configArgs;
   NamedValueSet configRecord;

#if defined( HWAFU )
   // Specify that the remote resource manager is to be used.
   configRecord.Add(AALRUNTIME_CONFIG_BROKER_SERVICE, "librrmbroker");
   configArgs.Add(AALRUNTIME_CONFIG_RECORD, &configRecord);
#endif

   // Start the Runtime and wait for the callback by sitting on the semaphore.
   //   the runtimeStarted() or runtimeStartFailed() callbacks should set m_bIsOK appropriately.
   if(!m_Runtime.start(configArgs)){
      m_bIsOK = false;
      return;
   }
   m_Sem.Wait();
   m_bIsOK = true;
}

/// @brief   Destructor
///
HelloALIVTPNLBApp::~HelloALIVTPNLBApp()
{
   m_Sem.Destroy();
}

/// @brief   run() is called from main performs the following:
///             - Allocate the appropriate ALI Service depending
///               on whether a hardware, ASE or software implementation is desired.
///             - Allocates the necessary buffers to be used by the NLB AFU algorithm
///             - Executes the NLB algorithm
///             - Cleans up.
///
btInt HelloALIVTPNLBApp::run()
{
   cout <<"========================"<<endl;
   cout <<"= Hello ALI NLB Sample ="<<endl;
   cout <<"========================"<<endl;

   // Request the Servcie we are interested in.

   // NOTE: This example is bypassing the Resource Manager's configuration record lookup
   //  mechanism.  Since the Resource Manager Implementation is a sample, it is subject to change.
   //  This example does illustrate the utility of having different implementations of a service all
   //  readily available and bound at run-time.
   NamedValueSet Manifest;
   NamedValueSet ConfigRecord;
   NamedValueSet featureFilter;
   btcString sGUID = MPF_VTP_BBB_GUID;

   unsigned int bufferSize;

#if defined( HWAFU )                /* Use FPGA hardware */
   // Service Library to use
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libHWALIAFU");

   // the AFUID to be passed to the Resource Manager. It will be used to locate the appropriate device.
   ConfigRecord.Add(keyRegAFU_ID,"C000C966-0D82-4272-9AEF-FE5F84570612");


   // indicate that this service needs to allocate an AIAService, too to talk to the HW
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_AIA_NAME, "libaia");

   #elif defined ( ASEAFU )         /* Use ASE based RTL simulation */
   Manifest.Add(keyRegHandle, 20);

   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libASEALIAFU");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

   #else                            /* default is Software Simulator */
#if 0 // NOT CURRRENTLY SUPPORTED
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libSWSimALIAFU");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);
#endif
   return -1;
#endif

   // Add the Config Record to the Manifest describing what we want to allocate
   Manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, &ConfigRecord);

   // in future, everything could be figured out by just giving the service name
   Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "Hello ALI NLB");

   MSG("Allocating ALIAFU Service");

   // Allocate the Service and wait for it to complete by sitting on the
   //   semaphore. The serviceAllocated() callback will be called if successful.
   //   If allocation fails the serviceAllocateFailed() should set m_bIsOK appropriately.
   //   (Refer to the serviceAllocated() callback to see how the Service's interfaces
   //    are collected.)
   //  Note that we are passing a custom transaction ID (created during app
   //   construction) to be able in serviceAllocated() to identify which
   //   service was allocated. This is only necessary if you are allocating more
   //   than one service from a single AAL service client.
   m_Runtime.allocService(dynamic_cast<IBase *>(this), Manifest, m_ALIAFUTranID);
   m_Sem.Wait();
   if(!m_bIsOK){
      ERR("ALIAFU allocation failed\n");
      goto done_0;
   }

   // Ask the ALI service for the VTP device feature header (DFH)
//   featureFilter.Add(ALI_GETFEATURE_ID_KEY, static_cast<ALI_GETFEATURE_ID_DATATYPE>(25));
   // featureFilter.Add(ALI_GETFEATURE_TYPE_KEY, static_cast<ALI_GETFEATURE_TYPE_DATATYPE>(2));
   // featureFilter.Add(ALI_GETFEATURE_GUID_KEY, static_cast<ALI_GETFEATURE_GUID_DATATYPE>(sGUID));
   // if (true != m_pALIMMIOService->mmioGetFeatureOffset(&m_VTPDFHOffset, featureFilter)) {
   //    ERR("No VTP feature\n");
   //    m_bIsOK = false;
   //    m_Result = -1;
   //    goto done_1;
   // }

   // Reuse Manifest and Configrecord for VTP service
   Manifest.Empty();
   ConfigRecord.Empty();

   // Allocate VTP service
   // Service Library to use
   ConfigRecord.Add(AAL_FACTORY_CREATE_CONFIGRECORD_FULL_SERVICE_NAME, "libMPF");
   ConfigRecord.Add(AAL_FACTORY_CREATE_SOFTWARE_SERVICE,true);

   // Add the Config Record to the Manifest describing what we want to allocate
   Manifest.Add(AAL_FACTORY_CREATE_CONFIGRECORD_INCLUDED, &ConfigRecord);

   // the VTPService will reuse the already established interfaces presented by
   // the ALIAFU service
   Manifest.Add(ALIAFU_IBASE_KEY, static_cast<ALIAFU_IBASE_DATATYPE>(m_pALIAFU_AALService));

   // MPFs feature ID, used to find correct features in DFH list
   Manifest.Add(MPF_FEATURE_ID_KEY, static_cast<MPF_FEATURE_ID_DATATYPE>(1));

   // in future, everything could be figured out by just giving the service name
   Manifest.Add(AAL_FACTORY_CREATE_SERVICENAME, "VTP");

   MSG("Allocating VTP Service");

   m_Runtime.allocService(dynamic_cast<IBase *>(this), Manifest, m_VTPTranID);
   m_Sem.Wait();
   if(!m_bIsOK){
      ERR("VTP Service allocation failed\n");
      goto done_0;
   }

   // Now that we have the Service and have saved the IVTP interface pointer
   //  we can now Allocate the 3 Workspaces used by the NLB algorithm. The buffer allocate
   //  function is synchronous so no need to wait on the semaphore

   // Note that we now hold two buffer interfaces, m_pALIBufferService and
   //  m_pVTPService. The latter will allocate shared memory buffers and update
   //  the VTP block's memory mapping table, and thus allow AFUs to access the
   //  shared buffer using virtual addresses. The former will only allocate the
   //  shred memory buffers, requiring the AFU to use physical addresses to
   //  access them.

   // Device Status Memory (DSM) is a structure defined by the NLB implementation.
   // FIXME: shouldn't these appear as a private feature header for the NLB AFU?

   // User Virtual address of the pointer is returned directly in the function
   // Remember, we're using VTP, so no need to convert to physical addresses
   if( ali_errnumOK != m_pVTPService->bufferAllocate(LPBK1_DSM_SIZE, &m_pDSM)){
      m_bIsOK = false;
      m_Result = -1;
      goto done_2;
   }

   // Save the size
   m_DSMSize = LPBK1_DSM_SIZE;

   // Repeat for the Input and Output Buffers
   if( ali_errnumOK != m_pVTPService->bufferAllocate(LPBK1_BUFFER_SIZE, &m_pInput)){
      m_bIsOK = false;
      m_Sem.Post(1);
      m_Result = -1;
      goto done_3;
   }

   m_InputSize = LPBK1_BUFFER_SIZE;

   if( ali_errnumOK !=  m_pVTPService->bufferAllocate(LPBK1_BUFFER_SIZE, &m_pOutput)){
      m_bIsOK = false;
      m_Sem.Post(1);
      m_Result = -1;
      goto done_4;
   }

   m_OutputSize = LPBK1_BUFFER_SIZE;

   //=============================
   // Now we have the NLB Service
   //   now we can use it
   //=============================
   MSG("Running Tests");
   MSG("  Shared buffer allocated for test:   " << m_InputSize / (1024*1024) <<
         " MBytes");

   if(true == m_bIsOK){

      MSG("m_pDSM == 0x" << std::hex << (btUnsigned64bitInt)m_pDSM );
      // Clear the DSM
      ::memset( m_pDSM, 0, m_DSMSize);

      MSG("m_pInput == 0x" << std::hex << (btUnsigned64bitInt)m_pInput );
      MSG("m_pOutput == 0x" << std::hex << (btUnsigned64bitInt)m_pOutput);
      // Initialize the source and destination buffers
      ::memset( m_pInput,  0, m_InputSize);     // Input initialized to 0
      ::memset( m_pOutput, 0, m_OutputSize);    // Output initialized to 0

      struct CacheLine {                           // Operate on cache lines
         btUnsigned32bitInt uint[16];
      };
      struct CacheLine *pCL = reinterpret_cast<struct CacheLine *>(m_pInput);
      for ( btUnsigned32bitInt i = 0; i < (m_InputSize) / CL(1) ; ++i ) {
         pCL[i].uint[15] = i+1;     // avoid zero lines in test patterns
      };                         // Cache-Line[n] is zero except last uint = n

      // Initiate AFU Reset
      m_pALIResetService->afuReset();

      // AFU Reset clear VTP, too, so reinitialize that
      // NOTE: this interface is likely to change in future releases of AAL.
      m_pVTPService->vtpReset();

      // Initiate DSM Reset
      // Set DSM base (virtual, since we have allocated using VTP), high then low
      m_pALIMMIOService->mmioWrite64(CSR_AFU_DSM_BASEL, (btUnsigned64bitInt)m_pDSM);

      //-----------------------------------------------------------------------
      // First test: copy one cacheline on the beginning of each 2MB page
      //-----------------------------------------------------------------------
      bufferSize = CL(1);

      for (btUnsigned64bitInt i = 0; i < m_InputSize / MB(2); i++) {
         MSG("---------- Iteration " << std::dec << i+1 << "/" << m_InputSize / MB(2) << " ---------");
#ifdef TEST_NEGATIVE
         // This check should fail, since we didn't run NLB yet
         if ( true == checkBuffers ( m_pInput+i*MB(2), m_pOutput+i*MB(2), bufferSize ) ) {
            ERR("Negative check failed.");
            ++m_Result;
            break;
         }
#endif
         if ( false == runNLB( m_pInput+i*MB(2), m_pOutput+i*MB(2), bufferSize, 0 ) ) {
            ERR("Test failed.");
            ++m_Result;
            break;
         }
         if ( false == checkBuffers ( m_pInput+i*MB(2), m_pOutput+i*MB(2), bufferSize ) ) {
            ERR("Check failed.");
            ++m_Result;
            break;
         }
      }

      //-----------------------------------------------------------------------
      // Second test: run a copy across two consecutive pages (2 MB)
      //-----------------------------------------------------------------------
      ::memset( m_pOutput, 0, m_OutputSize);    // Output initialized to 0
      bufferSize = 2 * MB(2);

#ifdef TEST_NEGATIVE
      // This check should fail, since we didn't run NLB yet
      if ( true == checkBuffers ( m_pInput, m_pOutput, bufferSize ) ) {
         ERR("Negative check failed.");
         ++m_Result;
         goto done_5;
      }
#endif
      if ( false == runNLB( m_pInput, m_pOutput, bufferSize, 0 ) ) {
         MSG("Test failed.");
         ++m_Result;
         goto done_5;
      }
      if ( false == checkBuffers ( m_pInput, m_pOutput, bufferSize ) ) {
         MSG("Check failed.");
         ++m_Result;
         goto done_5;
      }

   }
   MSG("Done Running Test");

   // Clean-up and return
done_5:
   m_pALIBufferService->bufferFree(m_pOutput);
done_4:
   m_pALIBufferService->bufferFree(m_pInput);
done_3:
   m_pALIBufferService->bufferFree(m_pDSM);

done_2:
   // Freed all three so now Release() the VTP Service through the Services IAALService::Release() method
   (dynamic_ptr<IAALService>(iidService, m_pVTP_AALService))->Release(TransactionID());
   m_Sem.Wait();

done_1:
   // Release() the HWALIAFU Service through the Services IAALService::Release() method
   (dynamic_ptr<IAALService>(iidService, m_pALIAFU_AALService))->Release(TransactionID());
   m_Sem.Wait();

done_0:
   m_Runtime.stop();
   m_Sem.Wait();

   return m_Result;
}


btBool HelloALIVTPNLBApp::checkBuffers( btVirtAddr bufA,
                                        btVirtAddr bufB,
                                        size_t     size )
{
   btVirtAddr p1, p2;
   int errpos = -1;
   // Check that output buffer now contains what was in input buffer, e.g. 0xAF
   for (p1 = bufA, p2 = bufB; p1 < bufA + size; p1++, p2++) {
      if ( *((unsigned char *)p1) != *((unsigned char *)p2)) {
         errpos = p1-bufA;
         break;
      }
   }

   if ( errpos != -1 ) {
      MSG("Output does NOT Match input, at offset " << errpos << ".");
      return false;
   } else {
      MSG("Output matches input");
      return true;
   }
}


btBool HelloALIVTPNLBApp::runNLB( btVirtAddr pInput, btVirtAddr pOutput, size_t size,
      btUnsigned32bitInt mode )
{
   ::memset( m_pDSM, 0, m_DSMSize);             // clear DSM

   MSG("-> Running NLB. Size: " << size << " Mode: " << mode);
   MSG("->   Offset  : " << std::dec << pInput-m_pInput);
   MSG("->   Virtual : 0x" << std::hex << (btUnsigned64bitInt)pInput);
   MSG("->   Physical: 0x" << std::hex <<
         (btUnsigned64bitInt)m_pVTPService->bufferGetIOVA(pInput));
   // Assert NLB reset
   m_pALIMMIOService->mmioWrite32(CSR_CTL, 0);

   //De-Assert NLB reset
   m_pALIMMIOService->mmioWrite32(CSR_CTL, 1);

   // Set input workspace address
   m_pALIMMIOService->mmioWrite64(CSR_SRC_ADDR, (btUnsigned64bitInt)(pInput) / CL(1));

   // Set output workspace address
   m_pALIMMIOService->mmioWrite64(CSR_DST_ADDR, (btUnsigned64bitInt)(pOutput) / CL(1));

   // Set the number of cache lines for the test
   m_pALIMMIOService->mmioWrite32(CSR_NUM_LINES, size / CL(1));

   // Set the test mode
   m_pALIMMIOService->mmioWrite32(CSR_CFG, mode);

   volatile bt32bitCSR *StatusAddr = (volatile bt32bitCSR *)
      (m_pDSM  + DSM_STATUS_TEST_COMPLETE);
   // Start the test
   m_pALIMMIOService->mmioWrite32(CSR_CTL, 3);

   // Wait for test completion
   while( 0 == ((*StatusAddr)&0x1) ) {
      SleepMicro(100);
   }
   MSG("Done Running NLB.");

   // Stop the device
   m_pALIMMIOService->mmioWrite32(CSR_CTL, 7);

   return true;
}

//=================
//  IServiceClient
//=================

// <begin IServiceClient interface>
void HelloALIVTPNLBApp::serviceAllocated(IBase *pServiceBase,
                                      TransactionID const &rTranID)
{
   // This application will allocate two different services (HWALIAFU and
   //  VTPService). We can tell them apart here by looking at the TransactionID.
   if (rTranID ==  m_ALIAFUTranID) {

      // Save the IBase for the Service. Through it we can get any other
      //  interface implemented by the Service
      m_pALIAFU_AALService = pServiceBase;
      ASSERT(NULL != m_pALIAFU_AALService);
      if ( NULL == m_pALIAFU_AALService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIBuffer as subclass interface. Used in Buffer Allocation and Free
      m_pALIBufferService = dynamic_ptr<IALIBuffer>(iidALI_BUFF_Service, pServiceBase);
      ASSERT(NULL != m_pALIBufferService);
      if ( NULL == m_pALIBufferService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIMMIO as subclass interface. Used to set/get MMIO Region
      m_pALIMMIOService = dynamic_ptr<IALIMMIO>(iidALI_MMIO_Service, pServiceBase);
      ASSERT(NULL != m_pALIMMIOService);
      if ( NULL == m_pALIMMIOService ) {
         m_bIsOK = false;
         return;
      }

      // Documentation says HWALIAFU Service publishes
      //    IALIReset as subclass interface. Used for resetting the AFU
      m_pALIResetService = dynamic_ptr<IALIReset>(iidALI_RSET_Service, pServiceBase);
      ASSERT(NULL != m_pALIResetService);
      if ( NULL == m_pALIResetService ) {
         m_bIsOK = false;
         return;
      }
   }
   else if (rTranID == m_VTPTranID) {

      // Save the IBase for the VTP Service.
       m_pVTP_AALService = pServiceBase;
       ASSERT(NULL != m_pVTP_AALService);
       if ( NULL == m_pVTP_AALService ) {
          m_bIsOK = false;
          return;
       }

       // Documentation says VTP Service publishes
       //    IVTP as subclass interface. Used for allocating shared
       //    buffers that support virtual addresses from AFU
       m_pVTPService = dynamic_ptr<IMPFVTP>(iidMPFVTPService, pServiceBase);
       ASSERT(NULL != m_pVTPService);
       if ( NULL == m_pVTPService ) {
          m_bIsOK = false;
          return;
       }
   }
   else
   {
      ERR("Unknown transaction ID encountered on serviceAllocated().");
      m_bIsOK = false;
      return;
   }

   MSG("Service Allocated");
   m_Sem.Post(1);
}

void HelloALIVTPNLBApp::serviceAllocateFailed(const IEvent &rEvent)
{
   ERR("Failed to allocate Service");
    PrintExceptionDescription(rEvent);
   ++m_Result;                     // Remember the error
   m_bIsOK = false;

   m_Sem.Post(1);
}

 void HelloALIVTPNLBApp::serviceReleased(TransactionID const &rTranID)
{
    MSG("Service Released");
   // Unblock Main()
   m_Sem.Post(1);
}

 void HelloALIVTPNLBApp::serviceReleaseFailed(const IEvent        &rEvent)
 {
    ERR("Failed to release a Service");
    PrintExceptionDescription(rEvent);
    m_bIsOK = false;
    m_Sem.Post(1);
 }


 void HelloALIVTPNLBApp::serviceEvent(const IEvent &rEvent)
{
   ERR("unexpected event 0x" << hex << rEvent.SubClassID());
   // The state machine may or may not stop here. It depends upon what happened.
   // A fatal error implies no more messages and so none of the other Post()
   //    will wake up.
   // OTOH, a notification message will simply print and continue.
}
// <end IServiceClient interface>


 //=================
 //  IRuntimeClient
 //=================

  // <begin IRuntimeClient interface>
 // Because this simple example has one object implementing both IRuntieCLient and IServiceClient
 //   some of these interfaces are redundant. We use the IServiceClient in such cases and ignore
 //   the RuntimeClient equivalent e.g.,. runtimeAllocateServiceSucceeded()

 void HelloALIVTPNLBApp::runtimeStarted( IRuntime            *pRuntime,
                                      const NamedValueSet &rConfigParms)
 {
    m_bIsOK = true;
    m_Sem.Post(1);
 }

 void HelloALIVTPNLBApp::runtimeStopped(IRuntime *pRuntime)
  {
     MSG("Runtime stopped");
     m_bIsOK = false;
     m_Sem.Post(1);
  }

 void HelloALIVTPNLBApp::runtimeStartFailed(const IEvent &rEvent)
 {
    ERR("Runtime start failed");
    PrintExceptionDescription(rEvent);
 }

 void HelloALIVTPNLBApp::runtimeStopFailed(const IEvent &rEvent)
 {
     MSG("Runtime stop failed");
     m_bIsOK = false;
     m_Sem.Post(1);
 }

 void HelloALIVTPNLBApp::runtimeAllocateServiceFailed( IEvent const &rEvent)
 {
    ERR("Runtime AllocateService failed");
    PrintExceptionDescription(rEvent);
 }

 void HelloALIVTPNLBApp::runtimeAllocateServiceSucceeded(IBase *pClient,
                                                     TransactionID const &rTranID)
 {
     MSG("Runtime Allocate Service Succeeded");
 }

 void HelloALIVTPNLBApp::runtimeEvent(const IEvent &rEvent)
 {
     MSG("Generic message handler (runtime)");
 }
 // <begin IRuntimeClient interface>

/// @} group HelloALIVTPNLB


//=============================================================================
// Name: main
// Description: Entry point to the application
// Inputs: none
// Outputs: none
// Comments: Main initializes the system. The rest of the example is implemented
//           in the object theApp.
//=============================================================================
int main(int argc, char *argv[])
{
   pAALLogger()->AddToMask(LM_All, LOG_INFO);
   HelloALIVTPNLBApp theApp;
   if(!theApp.isOK()){
      ERR("Runtime Failed to Start");
      exit(1);
   }
   btInt Result = theApp.run();

   MSG("Done");
   if (0 == Result) {
      MSG("======= SUCCESS =======");
   } else {
      MSG("!!!!!!! FAILURE !!!!!!!");
   }

   return Result;
}

