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
/// @file VTPService-internal.h
/// @brief Definitions for VTP Service.
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
#ifndef __CCI_MPF_SHIM_VTP_H__
#define __CCI_MPF_SHIM_VTP_H__
#include <aalsdk/aas/AALService.h>
#include <aalsdk/IServiceClient.h>
#include <aalsdk/osal/IDispatchable.h>

#include <aalsdk/service/IALIAFU.h>
#include <aalsdk/uaia/IAFUProxy.h>

#include "IMPF.h"              // Public MPF service interface
#include "MPFService.h"

#include "cci_mpf_shim_vtp_params.h"

BEGIN_NAMESPACE(AAL)

/// @addtogroup VTPService
/// @{

/// VTP page table physical address CSR offset
#define CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR 32

class MPFVTP : public CAASBase, public IMPFVTP
{
public:

   /// VTP constructor
   MPFVTP( IALIBuffer *pBufferService,
                   IALIMMIO   *pMMIOService,
                   btCSROffset vtpDFHOffset );

   // <IVTP>
   ali_errnum_e bufferAllocate( btWSSize             Length,
                                btVirtAddr          *pBufferptr )
   {
      return bufferAllocate(Length, pBufferptr, AAL::NamedValueSet());
   }
   ali_errnum_e bufferAllocate( btWSSize             Length,
                                btVirtAddr          *pBufferptr,
                                NamedValueSet const &rInputArgs )
   {
      NamedValueSet temp = NamedValueSet();
      return bufferAllocate(Length, pBufferptr, rInputArgs, temp);
   }
   ali_errnum_e bufferAllocate( btWSSize             Length,
                                btVirtAddr          *pBufferptr,
                                NamedValueSet const &rInputArgs,
                                NamedValueSet       &rOutputArgs );
   ali_errnum_e bufferFree(     btVirtAddr           Address );
   ali_errnum_e bufferFreeAll();
   btPhysAddr   bufferGetIOVA(  btVirtAddr           Address );

   // reinitialize VTP registers after AFU reset
   btBool vtpEnable( void );

   // FIXME: DEPRECATED
   btBool vtpReset( void );
   // </IVTP>

   btBool isOK( void ) { return m_isOK; }     // < status after initialization

protected:
   IALIBuffer            *m_pALIBuffer;
   IALIMMIO              *m_pALIMMIO;
   btCSROffset            m_dfhOffset;

   uint8_t               *m_pPageTable;
   btPhysAddr             m_PageTablePA;
   uint8_t               *m_pPageTableEnd;
   uint8_t               *m_pPageTableFree;

   btBool                 m_isOK;

private:
   //
   // Add a new page to the table.
   //
   void InsertPageMapping( const void* va, btPhysAddr pa );

   //
   // Convert addresses to their component bit ranges
   //
   inline void AddrComponentsFromVA( uint64_t va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset );

   inline void AddrComponentsFromVA(  const void* va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset );

   inline void AddrComponentsFromPA( uint64_t pa,
                                     uint64_t& idx,
                                     uint64_t& byteOffset );

   //
   // Construct a PTE from a virtual/physical address pair.
   //
   inline uint64_t AddrToPTE( uint64_t va, uint64_t pa );
   inline uint64_t AddrToPTE( const void* va, uint64_t pa );

   //
   // Read a PTE or table index currently in the table.
   //
   void ReadPTE( const uint8_t* pte, uint64_t& vaTag, uint64_t& paIdx );
   uint64_t ReadTableIdx( const uint8_t* p );

   //
   // Read a PTE or table index to the table.
   //
   void WritePTE( uint8_t* pte, uint64_t vaTag, uint64_t paIdx );
   void WriteTableIdx( uint8_t* p, uint64_t idx );

   // Dump the page table (debugging)
   void DumpPageTable();

   static const size_t pageSize = MB(2);
   static const size_t pageMask = ~(pageSize - 1);

   // Number of tag bits for a VA.  Tags are the VA bits not covered by
   // the page offset and the hash table index.
   static const uint32_t vaTagBits = CCI_PT_VA_BITS -
                                     CCI_PT_VA_IDX_BITS -
                                     CCI_PT_PAGE_OFFSET_BITS;

   // Size of a single PTE.  PTE is a tuple: VA tag and PA page index.
   // The size is rounded up to a multiple of bytes.
   static const uint32_t pteBytes = (vaTagBits + CCI_PT_PA_IDX_BITS + 7) / 8;

   // Size of a page table pointer rounded up to a multiple of bytes
   static const uint32_t ptIdxBytes = (CCI_PT_PA_IDX_BITS + 7) / 8;

   // Number of PTEs that fit in a line.  A line is the basic entry in
   // the hash table.  It holds as many PTEs as fit and ends with a pointer
   // to the next line, where the list of PTEs continues.
   static const uint32_t ptesPerLine = (CL(1) - ptIdxBytes) / pteBytes;

};



/// @}

END_NAMESPACE(AAL)

#endif //__VTP_H__

