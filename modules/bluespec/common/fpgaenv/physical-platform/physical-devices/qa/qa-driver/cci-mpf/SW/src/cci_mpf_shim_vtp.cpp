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

   AAL_DEBUG(LM_AFU, "Trying to allocate virtual buffer of size " << std::dec << Length << std::endl);

   btBool ret;
   void *pRet;                      // for error checking
   ali_errnum_e err;

   // FIXME: Input/OUtputArgs are ignored here...

   // Round request size to proper page size
   // If the tail (= remainder of Length that doesn't fill a large buffer)
   // is large enough, extend Length to fit large buffers. Otherwise, make sure
   // it at least fills 4k pages.
   size_t tail = Length % LARGE_PAGE_SIZE;
   AAL_DEBUG(LM_AFU, "tail: " << std::dec << tail << std::endl);
   if (tail > CCI_MPF_VTP_LARGE_PAGE_THRESHOLD) {
      // if tail is large enough, align with large page size
      Length = (Length + LARGE_PAGE_SIZE - 1) & LARGE_PAGE_MASK;
      tail = 0;
   } else {
      // otherwise, align with small page size
      Length = (Length + SMALL_PAGE_SIZE - 1) & SMALL_PAGE_MASK;
      tail = Length % LARGE_PAGE_SIZE;
   }
   size_t nLargeBuffers = Length / LARGE_PAGE_SIZE;
   size_t nSmallBuffers = (Length % LARGE_PAGE_SIZE) / SMALL_PAGE_SIZE;
   ASSERT( Length % SMALL_PAGE_SIZE == 0 );

   AAL_DEBUG(LM_AFU, "padded Length: " << std::dec << Length << std::endl);
   AAL_DEBUG(LM_AFU, std::dec << nLargeBuffers << " large and " << nSmallBuffers << " small buffers" << std::endl);

   // Map a region of the requested size.  This will reserve a virtual
   // memory address space.  As pages are allocated they will be
   // mapped into this space.
   //
   // An extra page is added to the request in order to enable alignment
   // of the base address.  Linux is only guaranteed to return 4 KB aligned
   // addresses and we want large page aligned virtual addresses.
   // TODO: Assumption is still that virtual buffer needs to be large-page
   //        (2MB) aligned, even smaller ones. Make that configurable.
   void* va_base;
   size_t va_base_len = Length + LARGE_PAGE_SIZE;
   va_base = mmap(NULL, va_base_len,
                  PROT_READ | PROT_WRITE,
                  MAP_SHARED | MAP_ANONYMOUS, -1, 0);
   ASSERT(va_base != MAP_FAILED);
   AAL_DEBUG(LM_AFU, "va_base " << std::hex << std::setw(2) << std::setfill('0') << va_base << std::endl);

   void* va_aligned = (void*)((size_t(va_base) + LARGE_PAGE_SIZE - 1) & LARGE_PAGE_MASK);
   AAL_DEBUG(LM_AFU, "va_aligned " << std::hex << std::setw(2) << std::setfill('0') << va_aligned << std::endl);

   // Trim off the unnecessary extra space after alignment
   size_t trim = LARGE_PAGE_SIZE - (size_t(va_aligned) - size_t(va_base));
   AAL_DEBUG(LM_AFU, "va_base_len trimmed by " << std::hex << std::setw(2) << std::setfill('0') << trim << " to " << va_base_len - trim << std::endl);
   pRet = mremap(va_base, va_base_len, va_base_len - trim, 0);
   ASSERT(va_base == pRet);
   va_base_len -= trim;

   // start at the end of the virtual buffer and work backwards
   // start with small buffers until we are done or  hit a large buffer
   // alingment boundary. Then continue with large buffers. If a large buffer
   // allocation fails, fall back to small pages.
   // TODO: make large page allocation threshold configurable

   void * va_alloc = (void *)(size_t(va_aligned) + Length);

   // -------------------------------------------------------------------------
   // small buffer allocation loop
   // -------------------------------------------------------------------------
   // Run to allocate small buffers until we can cover the remaining space with
   // large buffers.
   while ((size_t(va_alloc) & ( LARGE_PAGE_SIZE-1 )) != 0) {

      va_alloc = (void *)(size_t(va_alloc) - SMALL_PAGE_SIZE);

      // Shrink the reserved area in order to make a hole in the virtual
      // address space.
      pRet = mremap(va_base, va_base_len, va_base_len - SMALL_PAGE_SIZE, 0);
      ASSERT(va_base == pRet);
      va_base_len -= SMALL_PAGE_SIZE;

      // allocate buffer
      err = _allocate((btVirtAddr)va_alloc, SMALL_PAGE_SIZE);
      if (err != ali_errnumOK) {
         AAL_ERR(LM_AFU, "Unable to allocate buffer. Err: " << err);
         return err;
         // FIXME: leaking already allocated pages!
      }

      Length -= SMALL_PAGE_SIZE;
   }

   AAL_DEBUG(LM_AFU, "len remaining: " << std::dec << Length << std::endl);


   // -------------------------------------------------------------------------
   // large buffer allocation loop
   // -------------------------------------------------------------------------
   // Run for the remaining space, which should be an integer multiple of the
   // large buffer size in size, and aligned to large buffer boundaries. If
   // large buffer allocation fails, fall back to small buffers.
   size_t effPageSize = LARGE_PAGE_SIZE;     // page size used for actual allocations

   while (Length > 0) {

      va_alloc = (void *)(size_t(va_alloc) - effPageSize);

      // Shrink the reserved area in order to make a hole in the virtual
      // address space. If this is the last buffer to allocate, unmap reserved
      // area.
      if (va_base_len == effPageSize) {
         munmap(va_base, va_base_len);
         va_base_len = 0;
      } else {
         pRet = mremap(va_base, va_base_len, va_base_len - effPageSize, 0);
         ASSERT(va_base == pRet);
         va_base_len -= effPageSize;
      }

      // allocate buffer
      err = _allocate((btVirtAddr)va_alloc, effPageSize);
      if (err != ali_errnumOK) {
         if (effPageSize == LARGE_PAGE_SIZE) {
            // fall back to small buffers:
            // restore last large mapping
            if (va_base_len = 0) {
               // corner case: this was the last mapping - we destroyed it, so
               // try to restore it.
               va_base = mmap(va_alloc, LARGE_PAGE_SIZE,
                     PROT_READ | PROT_WRITE,
                     MAP_SHARED | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
               ASSERT(va_base == va_alloc);
            } else {
               // this was not the last mapping (or va_base is not aligned), so
               // we still have a valid reserved space. Just resize it back up.
               pRet = mremap(va_base, va_base_len, va_base_len + LARGE_PAGE_SIZE, 0);
               ASSERT(pRet == va_base);
            }
            va_base_len += LARGE_PAGE_SIZE;
            va_alloc = (void *)(size_t(va_alloc) + LARGE_PAGE_SIZE);
            effPageSize = SMALL_PAGE_SIZE;
            continue;    // try again with smal buffers
         } else {
            // already using small buffers, nowhere to fall back to.
            AAL_ERR(LM_AFU, "Unable to allocate buffer. Err: " << err);
            return err;
            // FIXME: leaking already allocated pages!
         }
      }

      // mapping successful, on to the next
      Length -= effPageSize;
   }

   // clean up
   if (va_base_len != 0)
   {
       munmap(va_base, va_base_len);
   }

   ptDumpPageTable();

   *pBufferptr = (btVirtAddr)va_aligned;
   return ali_errnumOK;
}

// allocate page of size pageSize to virtual address va and add entry to VTP
// page table
ali_errnum_e MPFVTP::_allocate(btVirtAddr va, size_t pageSize)
{
   ali_errnum_e err;
   MPFVTP_PAGE_SIZE mapType;

   // FIXME: can we reuse this? expensive! static?
   NamedValueSet *bufAllocArgs = new NamedValueSet();
   btVirtAddr alloc;

   AAL_DEBUG(LM_AFU, "_allocate(" << std::hex << std::setw(2) << std::setfill('0') << (void *)va << ", " << std::dec << (unsigned int)pageSize << ")" << std::endl);

   // determine mapping type for page table entry
   if (pageSize == LARGE_PAGE_SIZE) {
      mapType = MPFVTP_PAGE_2MB;
   } else if (pageSize == SMALL_PAGE_SIZE) {
      mapType = MPFVTP_PAGE_4KB;
   } else {
      AAL_ERR(LM_AFU, "Invalid page size." << std::endl);
      return ali_errnumBadParameter;
   }

   // allocate buffer at va
   bufAllocArgs->Add(ALI_MMAP_TARGET_VADDR_KEY, static_cast<ALI_MMAP_TARGET_VADDR_DATATYPE>(va));
   err = m_pALIBuffer->bufferAllocate(pageSize, &alloc, *bufAllocArgs);

   // insert VTP page table entry
   if (err == ali_errnumOK) {
      ASSERT(va == alloc);
      ptInsertPageMapping(btVirtAddr(va),
                          m_pALIBuffer->bufferGetIOVA((unsigned char *)va),
                          mapType);
   }
   delete bufAllocArgs;
   return err;
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
