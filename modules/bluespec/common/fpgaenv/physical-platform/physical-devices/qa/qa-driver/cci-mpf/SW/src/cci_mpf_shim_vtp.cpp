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
   size_t pt_size = (1LL << CCI_PT_LINE_IDX_BITS) * CL(1);
   err = m_pALIBuffer->bufferAllocate(pt_size, &m_pPageTable);
   ASSERT(err == ali_errnumOK && m_pPageTable);

   // clear table
   memset(m_pPageTable, 0, pt_size);

   // FIXME: bufferGetIOVA should take a btVirtAddr to be consistent
   m_PageTablePA = m_pALIBuffer->bufferGetIOVA((unsigned char *)m_pPageTable);

   m_pPageTableEnd = m_pPageTable + pt_size;

   // The page table is hashed.  It begins with lines devoted to the hash
   // table.  The remainder of the buffer is available for overflow lines.
   // Initialize the free pointer of overflow lines, which begins at the
   // end of the hash table.
   m_pPageTableFree = m_pPageTable + (1LL << CCI_PT_VA_IDX_BITS) * CL(1);
   ASSERT(m_pPageTableFree <= m_pPageTableEnd);

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
      InsertPageMapping(va_alloc, m_pALIBuffer->bufferGetIOVA((unsigned char *)buffer));

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

   DumpPageTable();

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
   // Get the hash index and VA tag
   uint64_t tag;
   uint64_t idx;
   uint64_t offset;
   AddrComponentsFromVA(Address, tag, idx, offset);

   // The idx field is the hash bucket in which the VA will be found.
   uint8_t* pte = m_pPageTable + idx * CL(1);

   // Search for a matching tag in the hash bucket.  The bucket is a set
   // of vectors PTEs chained in a linked list.
   while (true)
   {
      // Walk through one vector in one line
      for (int n = 0; n < ptesPerLine; n += 1)
      {
         uint64_t va_tag;
         uint64_t pa_idx;
         ReadPTE(pte, va_tag, pa_idx);

         if (va_tag == tag)
         {
            // Found it!
            return (pa_idx << CCI_PT_PAGE_OFFSET_BITS) | offset;
         }

         // End of the PTE list?
         if (va_tag == 0)
         {
            // Failed to find an entry for VA
            return 0;
         }

         pte += pteBytes;
      }

      // VA not found in current line.  Does this line of PTEs link to
      // another?
      pte = m_pPageTable + ReadTableIdx(pte) * CL(1);

      // End of list?  (Table index was NULL.)
      if (pte == m_pPageTable)
      {
         return 0;
      }
   }
}

btBool MPFVTP::vtpReset( void )
{
   AAL_WARNING(LM_AFU, "Using vtpReset(). This interface is deprecated. Use vtpEnable() instead." << std::endl);
   return vtpEnable();
}

btBool MPFVTP::vtpEnable( void )
{
   // FIXME: this is likely to change or disappear in beta!

   // Write page table physical address CSR
   return m_pALIMMIO->mmioWrite64(m_dfhOffset + CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR, m_PageTablePA / CL(1));
}

//-----------------------------------------------------------------------------
// Private functions
//-----------------------------------------------------------------------------

void MPFVTP::InsertPageMapping( const void* va, btPhysAddr pa )
{
    AAL_DEBUG(LM_AFU, "Map " << std::hex << std::setw(2) <<
                      std::setfill('0') << va << " at " << pa << std::endl);

    //
    // VA components are the offset within the 2MB-aligned page, the index
    // within the direct-mapped page table hash vector and the remaining high
    // address bits: the tag.
    //
    uint64_t va_tag;
    uint64_t va_idx;
    uint64_t va_offset;
    AddrComponentsFromVA(va, va_tag, va_idx, va_offset);
    ASSERT(va_offset == 0);

    //
    // PA components are the offset within the 2MB-aligned page and the
    // index of the 2MB aligned physical page (low bits dropped).
    //
    uint64_t pa_idx;
    uint64_t pa_offset;
    AddrComponentsFromPA(pa, pa_idx, pa_offset);
    ASSERT(pa_offset == 0);

    //
    // The page table is hashed by the VA index.  Compute the address of
    // the line given the hash.
    //
    uint8_t* p = m_pPageTable + va_idx * CL(1);

    //
    // Find a free entry.
    //
    uint32_t n = 0;
    while (true)
    {
        if (n++ != ptesPerLine)
        {
            // Walking PTEs in a line
            uint64_t tmp_va_tag;
            uint64_t tmp_pa_idx;
            ReadPTE(p, tmp_va_tag, tmp_pa_idx);

            if (tmp_va_tag == 0)
            {
                // Found a free entry
                break;
            }

            // Entry was busy.  Move on to the next one.
            p += pteBytes;
        }
        else
        {
            // End of the line.  Is there an overflow line already?
            n = 0;

            uint64_t next_idx = ReadTableIdx(p);
            if (next_idx != 0)
            {
                // Overflow allocated.  Switch to it and keep searching.
                p = m_pPageTable + next_idx * CL(1);
            }
            else
            {
                // Need a new overflow line.  Is there space in the page table?
                ASSERT(m_pPageTableFree < m_pPageTableEnd);

                // Add a next line pointer to the current entry.
                WriteTableIdx(p, (m_pPageTableFree - m_pPageTable) / CL(1));
                p = m_pPageTableFree;
                m_pPageTableFree += CL(1);

                // Write the new PTE at p.
                break;
            }
        }
    }

    // Add the new PTE
    WritePTE(p, va_tag, pa_idx);
}

void MPFVTP::ReadPTE( const uint8_t* pte, uint64_t& vaTag, uint64_t& paIdx )
{
    // Might not be a natural size so use memcpy
    uint64_t e = 0;
    memcpy(&e, pte, pteBytes);

    paIdx = e & ((1LL << CCI_PT_PA_IDX_BITS) - 1);

    vaTag = e >> CCI_PT_PA_IDX_BITS;
    vaTag &= (1LL << vaTagBits) - 1;

    // VA is sign extended from its size to 64 bits
    if (CCI_PT_VA_BITS != 64)
    {
        vaTag <<= (64 - vaTagBits);
        vaTag = uint64_t(int64_t(vaTag) >> (64 - vaTagBits));
    }
}

uint64_t MPFVTP::ReadTableIdx( const uint8_t* p )
{
    // Might not be a natural size
    uint64_t e = 0;
    memcpy(&e, p, (CCI_PT_LINE_IDX_BITS + 7) / 8);

    return e & ((1LL << CCI_PT_LINE_IDX_BITS) - 1);
}

void MPFVTP::WritePTE( uint8_t* pte, uint64_t vaTag, uint64_t paIdx )
{
    uint64_t p = AddrToPTE(vaTag, paIdx);

    // Might not be a natural size so use memcpy
    memcpy(pte, &p, pteBytes);
}

void MPFVTP::WriteTableIdx( uint8_t* p, uint64_t idx )
{
    // Might not be a natural size
    memcpy(p, &idx, (CCI_PT_LINE_IDX_BITS + 7) / 8);
}

void MPFVTP::DumpPageTable()
{
     AAL_DEBUG(LM_AFU, "Page table dump: " << std::endl);
     AAL_DEBUG(LM_AFU, (1LL << CCI_PT_LINE_IDX_BITS) << " lines " <<
                       ptesPerLine << " PTEs per line, max memory represented in PTE " <<
                       ((1LL << CCI_PT_LINE_IDX_BITS) * ptesPerLine * 2) / 1024 <<
                       " GB" << std::endl);
//std::hex << std::setw(2) << std::setfill('0') << (void*)buffer << " to " << va_alloc << std::endl);

    // Loop through all lines in the hash table
    for (int hash_idx = 0; hash_idx < (1LL << CCI_PT_VA_IDX_BITS); hash_idx += 1)
    {
        int cur_idx = hash_idx;
        uint8_t* pte = m_pPageTable + hash_idx * CL(1);

        // Loop over all lines in the hash group
        while (true)
        {
            int n;
            // Loop over all PTEs in a single line
            for (n = 0; n < ptesPerLine; n += 1)
            {
                uint64_t va_tag;
                uint64_t pa_idx;
                ReadPTE(pte, va_tag, pa_idx);

                // End of the PTE list within the current hash group?
                if (va_tag == 0) break;

                //
                // The VA in a PTE is the combination of the tag (stored
                // in the PTE) and the hash table index.  The table index
                // is mapped directly from the low bits of the VA's line
                // address.
                //
                // The PA in a PTE is stored as the index of the 2MB-aligned
                // physical address.
                AAL_DEBUG(LM_AFU, "    " << std::dec << hash_idx << "/" << cur_idx <<
                          ":\t\tVA " << std::hex << std::setw(2) << std::setfill('0') <<
                          ((va_tag << (CCI_PT_VA_IDX_BITS + CCI_PT_PAGE_OFFSET_BITS)) |
                          (uint64_t(hash_idx) << CCI_PT_PAGE_OFFSET_BITS)) << " -> PA " <<
                          std::hex << std::setw(2) << std::setfill('0') <<
                          pa_idx << CCI_PT_PAGE_OFFSET_BITS << std::endl);
                pte += pteBytes;
            }

            // If the PTE list within the current hash group is incomplete then
            // we have walked all PTEs in the line.
            if (n != ptesPerLine) break;

            // Follow the next pointer to the connected line holding another
            // vector of PTEs.
            cur_idx = ReadTableIdx(pte);
            pte = m_pPageTable + cur_idx * CL(1);
            // End of list?  (Table index was NULL.)
            if (pte == m_pPageTable) break;
        }
    }
}

inline void MPFVTP::AddrComponentsFromVA( uint64_t va,
                                       uint64_t& tag,
                                       uint64_t& idx,
                                       uint64_t& byteOffset )
{
   uint64_t v = va;

   byteOffset = v & ((1LL << CCI_PT_PAGE_OFFSET_BITS) - 1);
   v >>= CCI_PT_PAGE_OFFSET_BITS;

   idx = v & ((1LL << CCI_PT_VA_IDX_BITS) - 1);
   v >>= CCI_PT_VA_IDX_BITS;

   tag = v & ((1LL << vaTagBits) - 1);

   // Make sure no address bits were lost in the conversion.  The high bits
   // beyond CCI_PT_VA_BITS are sign extended.
   if (CCI_PT_VA_BITS != 64)
   {
      int64_t va_check = va;
      // Shift all but the high bit of the VA range to the right.  All the
      // resulting bits must match.
      va_check >>= (CCI_PT_VA_BITS - 1);
      ASSERT((va_check == 0) || (va_check == -1));
   }
}


inline void MPFVTP::AddrComponentsFromVA( const void *va,
                                       uint64_t& tag,
                                       uint64_t& idx,
                                       uint64_t& byteOffset )
{
   AddrComponentsFromVA(uint64_t(va), tag, idx, byteOffset);
}

inline void MPFVTP::AddrComponentsFromPA( uint64_t pa,
                                       uint64_t& idx,
                                       uint64_t& byteOffset )
{
   uint64_t p = pa;

   byteOffset = p & ((1LL << CCI_PT_PAGE_OFFSET_BITS) - 1);
   p >>= CCI_PT_PAGE_OFFSET_BITS;

   idx = p & ((1LL << CCI_PT_PA_IDX_BITS) - 1);
   p >>= CCI_PT_PA_IDX_BITS;

   // PA_IDX_BITS must be large enough to represent all physical pages
   ASSERT(p == 0);
}

inline uint64_t MPFVTP::AddrToPTE( uint64_t va, uint64_t pa )
{
   ASSERT((pa & ~((1LL << CCI_PT_PA_IDX_BITS) - 1)) == 0);

   return ((va << CCI_PT_PA_IDX_BITS) | pa);
}

inline uint64_t MPFVTP::AddrToPTE( const void* va, uint64_t pa )
{
   return AddrToPTE(uint64_t(va), pa);
}
/// @} group VTPService

END_NAMESPACE(AAL)

