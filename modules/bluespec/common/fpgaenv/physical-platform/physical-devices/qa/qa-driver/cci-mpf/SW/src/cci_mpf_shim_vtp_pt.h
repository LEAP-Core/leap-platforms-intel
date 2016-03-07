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
/// @file cci_mpf_shim_vtp_pt.h
/// @brief Page table creation for MPF VTP service.
/// @ingroup VTPService
/// @verbatim
///
/// Construct a page table for translating virtual addresses shared between
/// FPGA and host process to physical addresses.
///
/// Note: this is not an AAL service, but a component of the MPF service (which
/// is).
///
/// AUTHOR: Michael Adler, Intel Corporation
///
/// HISTORY:
/// WHEN:          WHO:     WHAT:
/// 03/05/2016     MA       Initial version
/// @endverbatim
//****************************************************************************

#ifndef __CCI_MPF_SHIM_VTP_PT_H__
#define __CCI_MPF_SHIM_VTP_PT_H__

#include <aalsdk/AALTypes.h>
#include <aalsdk/utils/Utilities.h>

#include "cci_mpf_shim_vtp_params.h"

BEGIN_NAMESPACE(AAL)

/// @addtogroup VTPService
/// @{

//
// The page table supports two physical page sizes.
//
typedef enum
{
    MPFVTP_PAGE_4KB,
    MPFVTP_PAGE_2MB
}
MPFVTP_PAGE_SIZE;


//
// MPFVTP_PAGE_TABLE -- Page table management.
//
//  This page table management code supports multiple versions of AAL
//  and multiple FPGA interfaces.  In order to do this it uses only a
//  handful of AAL types and include files.  Otherwise, types are
//  standard C types.
//
class MPFVTP_PAGE_TABLE
{
  public:
    // VTP page table constructor
    MPFVTP_PAGE_TABLE();

    // Initialize page table
    bool ptInitialize();

    // Return the physical address of the root of the page table.  This
    // address must be passed to the FPGA-side page table walker.
    btPhysAddr ptGetPageTableRootPA() const;

    // Add a new page to the table
    bool ptInsertPageMapping(btVirtAddr va,
                             btPhysAddr pa,
                             MPFVTP_PAGE_SIZE size);

    // Translate an address from virtual to physical.
    bool ptTranslateVAtoPA(btVirtAddr va,
                           btPhysAddr *pa);

    // Dump the page table (debugging)
    void ptDumpPageTable();

  private:
    // The parent class must provide a method for allocating memory
    // shared with the FPGA, used here to construct the page table that
    // will be walked in hardware.
    virtual btVirtAddr ptAllocSharedPage(btWSSize length, btPhysAddr* pa) = 0;

  private:
    uint8_t               *m_pPageTable;
    btPhysAddr             m_pPageTablePA;
    uint8_t               *m_pPageTableEnd;
    uint8_t               *m_pPageTableFree;

    //
    // Convert addresses to their component bit ranges
    //
    inline void AddrComponentsFromVA(uint64_t va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);

    inline void AddrComponentsFromVA(const void* va,
                                     uint64_t& tag,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);

    inline void AddrComponentsFromPA(uint64_t pa,
                                     uint64_t& idx,
                                     uint64_t& byteOffset);

    //
    // Construct a PTE from a virtual/physical address pair.
    //
    inline uint64_t AddrToPTE(uint64_t va, uint64_t pa);
    inline uint64_t AddrToPTE(const void* va, uint64_t pa);

    //
    // Read a PTE or table index currently in the table.
    //
    void ReadPTE(const uint8_t* pte, uint64_t& vaTag, uint64_t& paIdx);
    uint64_t ReadTableIdx(const uint8_t* p);

    //
    // Read a PTE or table index to the table.
    //
    void WritePTE(uint8_t* pte, uint64_t vaTag, uint64_t paIdx);
    void WriteTableIdx(uint8_t* p, uint64_t idx);

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

#endif // __CCI_MPF_SHIM_VTP_PT_H__
