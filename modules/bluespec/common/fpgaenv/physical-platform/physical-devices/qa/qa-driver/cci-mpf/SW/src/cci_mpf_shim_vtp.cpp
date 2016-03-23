// Copyright(c) 2015-2016, Intel Corporation
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
/// @file cci_mpf_shim_vtp.cpp
/// @brief Implementation of MPFVTP.
/// @ingroup VTPService
/// @verbatim
/// Intel(R) QuickAssist Technology Accelerator Abstraction Layer
/// Virtual-to-Physical address translation component class
///
/// Provides methods for access to the VTP BBB for address translation.
/// Assumes a VTP BBB DFH to be detected and present.
///
/// On initialization, allocates shared buffer for VTP page hash and
/// communicates its location to VTP BBB.
///
/// Provides synchronous methods to update page hash on shared buffer
/// allocation.
///
/// Note: this is not an AAL service, but a component of the MPF service (which
/// is).
///
/// AUTHORS: Enno Luebbers, Intel Corporation
///          Michael Adler, Intel Corporation
///
/// HISTORY:
/// WHEN:          WHO:     WHAT:
/// 01/15/2016     EL       Initial version@endverbatim
//****************************************************************************
#ifdef HAVE_CONFIG_H
# include <config.h>
#endif // HAVE_CONFIG_H

#include <aalsdk/AAL.h>
#include <aalsdk/aas/AALServiceModule.h>
#include <aalsdk/osal/Sleep.h>

#include <aalsdk/AALLoggerExtern.h>              // Logger
#include <aalsdk/utils/AALEventUtilities.h>      // Used for UnWrapAndReThrow()

#include <aalsdk/aas/AALInProcServiceFactory.h>  // Defines InProc Service Factory
#include <aalsdk/service/IALIAFU.h>

#include "cci_mpf_shim_vtp.h"

BEGIN_NAMESPACE(AAL)


//=============================================================================
// Typedefs and Constants
//=============================================================================



/////////////////////////////////////////////////////////////////////////////
//////                                                                ///////
//////                                                                ///////
/////                            VTP Service                           //////
//////                                                                ///////
//////                                                                ///////
/////////////////////////////////////////////////////////////////////////////


/// @addtogroup VTPService
/// @{

//-----------------------------------------------------------------------------
// Public functions
//-----------------------------------------------------------------------------

MPFVTP::MPFVTP( IALIBuffer *pBufferService,
                IALIMMIO   *pMMIOService,
                btCSROffset vtpDFHOffset ) : m_pALIBuffer( pBufferService),
                                             m_pALIMMIO( pMMIOService ),
                                             m_dfhOffset( vtpDFHOffset ),
                                             m_isOK( false )
{
   ali_errnum_e err;
   btBool ret;                                // for error checking

   ASSERT( m_pALIBuffer != NULL );
   ASSERT( m_pALIMMIO != NULL );
   ASSERT( m_dfhOffset != -1 );

   // Check BBB GUID (are we really a VTP?)
   btcString sGUID = MPF_VTP_BBB_GUID;
   AAL_GUID_t structGUID;
   btUnsigned64bitInt readBuf[2];

   ret = m_pALIMMIO->mmioRead64(m_dfhOffset + 8, &readBuf[0]);
   ASSERT(ret);
   ret = m_pALIMMIO->mmioRead64(m_dfhOffset + 16, &readBuf[1]);
   ASSERT(ret);
   if ( 0 != strncmp( sGUID, GUIDStringFromStruct(GUIDStructFrom2xU64(readBuf[1], readBuf[0])).c_str(), 36 ) ) {
      AAL_ERR(LM_AFU, "Feature GUID does not match VTP GUID.");
      m_isOK = false;
      return;
   }

   AAL_INFO(LM_AFU, "Found and successfully identified VTP feature." << std::endl);

   // Allocate the page table.  The size of the page table is a function
   // of the PTE index space.
   ret = ptInitialize();
   ASSERT(ret);

   // Tell the hardware the address of the table
   ret = vtpEnable();
   ASSERT(ret);

   m_isOK = true;
}


ali_errnum_e MPFVTP::bufferAllocate( btWSSize             Length,
                                     btVirtAddr          *pBufferptr,
                                     NamedValueSet const &rInputArgs,
                                     NamedValueSet       &rOutputArgs )
{
   AutoLock(this);

   void *pRet;                      // for error checking

   // FIXME: Input/OUtputArgs are ignored here...
   // FIXME: we can support optArg ALI_MMAP_TARGET_VADDR_KEY also for
   //        large VTP mappings (need to add MAP_FIXED to the first mmap
   //        below).

   // Align request to page size
   Length = (Length + pageSize - 1) & pageMask;

   // Map a region of the requested size.  This will reserve a virtual
   // memory address space.  As pages are allocated they will be
   // mapped into this space.
   //
   // An extra page is added to the request in order to enable alignment
   // of the base address.  Linux is only guaranteed to return 4 KB aligned
   // addresses and we want large page aligned virtual addresses.
   void* va_base;
   size_t va_base_len = Length + pageSize;
   va_base = mmap(NULL, va_base_len,
                  PROT_READ | PROT_WRITE,
                  MAP_SHARED | MAP_ANONYMOUS, -1, 0);
   ASSERT(va_base != MAP_FAILED);
   AAL_DEBUG(LM_AFU, "va_base " << std::hex << std::setw(2) << std::setfill('0') << va_base << std::endl);

   void* va_aligned = (void*)((size_t(va_base) + pageSize - 1) & pageMask);
   AAL_DEBUG(LM_AFU, "va_aligned " << std::hex << std::setw(2) << std::setfill('0') << va_aligned << std::endl);

   // Trim off the unnecessary extra space after alignment
   size_t trim = pageSize - (size_t(va_aligned) - size_t(va_base));
   AAL_DEBUG(LM_AFU, "va_base_len trimmed by " << std::hex << std::setw(2) << std::setfill('0') << trim << " to " << va_base_len - trim << std::endl);
   pRet = mremap(va_base, va_base_len, va_base_len - trim, 0);
   ASSERT(va_base == pRet);
   va_base_len -= trim;

   // How many page size buffers are needed to satisfy the request?
   size_t n_buffers = Length / pageSize;

   // Buffer mapping will begin at the end of the va_aligned region
   void* va_alloc = (void*)(size_t(va_aligned) + pageSize * (n_buffers - 1));

   // Prepare bufferAllocate's optional argument to mmap() to a specific address
   NamedValueSet *bufAllocArgs = new NamedValueSet();

   // Allocate the buffers
   for (size_t i = 0; i < n_buffers; i++)
   {
      // Shrink the reserved area in order to make a hole in the virtual
      // address space.
      if (va_base_len == pageSize)
      {
         munmap(va_base, va_base_len);
         va_base_len = 0;
      }
      else
      {
         pRet = mremap(va_base, va_base_len, va_base_len - pageSize, 0);
         ASSERT(va_base == pRet);
         va_base_len -= pageSize;
      }

      // set target virtual address for new buffer
      bufAllocArgs->Add(ALI_MMAP_TARGET_VADDR_KEY, static_cast<ALI_MMAP_TARGET_VADDR_DATATYPE>(va_alloc));

      // Get a page size buffer
      void *buffer;
      ali_errnum_e err = m_pALIBuffer->bufferAllocate(pageSize, (btVirtAddr*)&buffer, *bufAllocArgs);
      ASSERT(err == ali_errnumOK && buffer != NULL);

      // Handle allocation errors
      // Possible causes for failure:
      //    not enough memory
      //    not able to allocate the requested size
      //    ...?
      if (err != ali_errnumOK) {
         AAL_ERR(LM_AFU, "Unable to allocate buffer. Err: " << err);
         return err;
      }

      // If we didn't get the mapping on our bufferAllocate(), move the shared
      // buffer's VA to the proper slot
      // This should not happen, as we requested the proper VA above.
      // TODO: remove
      ASSERT(buffer == va_alloc);
      if (buffer != va_alloc)
      {
         AAL_DEBUG(LM_AFU, "remap " << std::hex << std::setw(2) << std::setfill('0') << (void*)buffer << " to " << va_alloc << std::endl);
         pRet = mremap((void*)buffer, pageSize, pageSize,
                        MREMAP_MAYMOVE | MREMAP_FIXED,
                        va_alloc);
         ASSERT(va_alloc == pRet);
      }

      // Add the mapping to the page table
      ptInsertPageMapping(btVirtAddr(va_alloc),
                          m_pALIBuffer->bufferGetIOVA((unsigned char *)buffer),
                          MPFVTP_PAGE_2MB);

      // Next VA
      va_alloc = (void*)(size_t(va_alloc) - pageSize);

      ASSERT((m_pALIBuffer->bufferGetIOVA((unsigned char *)buffer) & ~pageMask) == 0);

      // prepare optArgs for next allocation
      bufAllocArgs->Delete(ALI_MMAP_TARGET_VADDR_KEY);

   }

   delete bufAllocArgs;

   if (va_base_len != 0)
   {
       munmap(va_base, va_base_len);
   }

   ptDumpPageTable();

   *pBufferptr = (btVirtAddr)va_aligned;
   return ali_errnumOK;
}

ali_errnum_e MPFVTP::bufferFree( btVirtAddr Address)
{
   // TODO: not implemented
   AAL_ERR(LM_All, "NOT IMPLEMENTED" << std::endl);
   return ali_errnumNoMem;
}

ali_errnum_e MPFVTP::bufferFreeAll()
{
   // TODO: not implemented
   AAL_ERR(LM_All, "NOT IMPLEMENTED" << std::endl);
   return ali_errnumNoMem;
}

btPhysAddr MPFVTP::bufferGetIOVA( btVirtAddr Address)
{
   bool ret;
   btPhysAddr pa;

   ret = ptTranslateVAtoPA(Address, &pa);
   ASSERT(ret);

   return pa;
}

btBool MPFVTP::vtpReset( void )
{
   m_pALIMMIO->mmioWrite64(m_dfhOffset + CCI_MPF_VTP_CSR_MODE, 2);

   return vtpEnable();
}

btBool MPFVTP::vtpEnable( void )
{
   // Write page table physical address CSR
   m_pALIMMIO->mmioWrite64(m_dfhOffset + CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR,
                           ptGetPageTableRootPA() / CL(1));

   // Enable VTP
   m_pALIMMIO->mmioWrite64(m_dfhOffset + CCI_MPF_VTP_CSR_MODE, 1);
}

// Return a statistics counter
btUnsigned64bitInt MPFVTP::vtpGetCounter( t_cci_mpf_vtp_csr_offsets stat )
{

   btUnsigned64bitInt cnt;
   btBool ret;

   ret = m_pALIMMIO->mmioRead64(m_dfhOffset + stat, &cnt);
   ASSERT(ret);

   return cnt;
}


//-----------------------------------------------------------------------------
// Private functions
//-----------------------------------------------------------------------------

btVirtAddr
MPFVTP::ptAllocSharedPage(btWSSize length, btPhysAddr* pa)
{
   ali_errnum_e err;
   btVirtAddr va;

   err = m_pALIBuffer->bufferAllocate(length, &va);
   ASSERT(err == ali_errnumOK && va);

   *pa = m_pALIBuffer->bufferGetIOVA((unsigned char *)va);
   return va;
}

/// @} group VTPService

END_NAMESPACE(AAL)

