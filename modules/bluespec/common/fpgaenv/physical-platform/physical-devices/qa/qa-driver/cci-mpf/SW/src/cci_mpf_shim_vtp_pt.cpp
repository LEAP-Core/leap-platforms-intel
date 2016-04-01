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
/// @file cci_mpf_shim_vtp_pt.cpp
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

#include <assert.h>

#include "cci_mpf_shim_vtp_pt.h"


BEGIN_NAMESPACE(AAL)


/////////////////////////////////////////////////////////////////////////////
//////                                                                ///////
//////                                                                ///////
/////                    VTP Page Table Management                     //////
//////                                                                ///////
//////                                                                ///////
/////////////////////////////////////////////////////////////////////////////

//
// The page table managed here looks very much like a standard x86_64
// hierarchical page table.  It is composed of a tree of 4KB pages, with
// each page holding a vector of 512 64-bit physical addresses.  Each level
// in the tree is selected directly from 9 bit chunks of a virtual address.
// Like x86_64 processors, only the low 48 bits of the virtual address are
// mapped.  Bits 39-47 select the index in the root of the page table,
// which is a physical address pointing to the mapping of the 2nd level
// bits 30-38, etc.  The search proceeds down the tree until a mapping is
// found.
//
// Since pages are aligned on at least 4KB boundaries, at least the low
// 12 bits of any value in the table are zero.  We use some of these bits
// as flags.  Bit 0 set indicates the mapping is complete.  The current
// implementation supports both 4KB and 2MB pages.  Bit 0 will be set
// after searching 3 levels for 2MB pages and 4 levels for 4KB pages.
// Bit 1 indicates no mapping exists and the search has failed.
//
// | 47 ---- 39 | 38 ---- 30 | 29 ---- 21 | 20 ---- 12 | 11 ---------- 0 |
//     9 bits       9 bits       9 bits       9 bits   ^ 4KB page offset ^
//                                        ^        2MB page offset       ^
//
//

/// @addtogroup VTPService
/// @{

//-----------------------------------------------------------------------------
// Public functions
//-----------------------------------------------------------------------------

MPFVTP_PAGE_TABLE::MPFVTP_PAGE_TABLE()
{
}


MPFVTP_PAGE_TABLE::~MPFVTP_PAGE_TABLE()
{
    // We should release the page table here.
}


bool
MPFVTP_PAGE_TABLE::ptInitialize()
{
    // Allocate the roots of both the virtual to physical page table passed
    // to the FPGA and the reverse physical to virtual table used in
    // this module to walk the virtual to physical table.

    // VtoP is shared with the hardware
    ptVtoP = MPFVTP_PT_TREE(ptAllocSharedPage(sizeof(MPFVTP_PT_TREE_CLASS),
                                              &m_pPageTablePA));
    ptVtoP->Reset();

    // PtoV is private to software
    ptPtoV = new MPFVTP_PT_TREE_CLASS();

    return true;
}


btPhysAddr
MPFVTP_PAGE_TABLE::ptGetPageTableRootPA() const
{
    return m_pPageTablePA;
}


bool
MPFVTP_PAGE_TABLE::ptInsertPageMapping(
    btVirtAddr va,
    btPhysAddr pa,
    MPFVTP_PAGE_SIZE size)
{
    // Are the addresses reasonable?
    uint64_t mask = (size == MPFVTP_PAGE_4KB) ? (1 << 12) - 1 :
                                                (1 << 21) - 1;
    assert((uint64_t(va) & mask) == 0);
    assert((pa & mask) == 0);

    uint32_t depth = (size == MPFVTP_PAGE_4KB) ? 4 : 3;

    AddVAtoPA(va, pa, depth);

    return true;
}


bool
MPFVTP_PAGE_TABLE::ptTranslateVAtoPA(btVirtAddr va,
                                     btPhysAddr *pa)
{
    MPFVTP_PT_TREE table = ptVtoP;

    uint32_t depth = 4;
    while (depth--)
    {
        // Index in the current level
        uint64_t idx = ptIdxFromAddr(uint64_t(va), depth);

        if (! table->EntryExists(idx)) return false;

        if (table->EntryIsTerminal(idx))
        {
            *pa = btPhysAddr(table->GetTranslatedAddr(idx));
            return true;
        }

        // Walk down to child
        btPhysAddr child_pa = table->GetChildAddr(idx);
        btVirtAddr child_va;
        if (! ptTranslatePAtoVA(child_pa, &child_va)) return false;
        table = MPFVTP_PT_TREE(child_va);
    }

    return false;
}


void
MPFVTP_PAGE_TABLE::ptDumpPageTable()
{
    DumpPageTableVAtoPA(ptVtoP, 0, 4);
}


//-----------------------------------------------------------------------------
// Private functions
//-----------------------------------------------------------------------------

bool
MPFVTP_PAGE_TABLE::ptTranslatePAtoVA(btPhysAddr pa, btVirtAddr *va)
{
    MPFVTP_PT_TREE table = ptPtoV;

    uint32_t depth = 4;
    while (depth--)
    {
        // Index in the current level
        uint64_t idx = ptIdxFromAddr(uint64_t(pa), depth);

        if (! table->EntryExists(idx)) return false;

        if (table->EntryIsTerminal(idx))
        {
            *va = btVirtAddr(table->GetTranslatedAddr(idx));
            return true;
        }

        // Walk down to child
        table = MPFVTP_PT_TREE(table->GetChildAddr(idx));
    }

    return false;
}


bool
MPFVTP_PAGE_TABLE::AddVAtoPA(btVirtAddr va, btPhysAddr pa, uint32_t depth)
{
    MPFVTP_PT_TREE table = ptVtoP;

    // Index in the leaf page
    uint64_t leaf_idx = ptIdxFromAddr(uint64_t(va), 4 - depth);

    uint32_t cur_depth = 4;
    while (--depth)
    {
        // Drop 4KB page offset
        uint64_t idx = ptIdxFromAddr(uint64_t(va), --cur_depth);

        // Need a new page in the table?
        if (! table->EntryExists(idx))
        {
            btPhysAddr pt_p;
            btVirtAddr pt_v = ptAllocSharedPage(sizeof(MPFVTP_PT_TREE_CLASS),
                                                &pt_p);
            MPFVTP_PT_TREE child_table = MPFVTP_PT_TREE(pt_v);
            child_table->Reset();

            // Add new page to physical to virtual translation so the table
            // can be walked in software
            if (! AddPAtoVA(pt_p, pt_v, 4)) return false;

            // Add new page to the FPGA-visible virtual to physical table
            table->InsertChildAddr(idx, pt_p);
        }

        // Are we being asked to add an entry below a larger region that
        // is already mapped?
        if (table->EntryIsTerminal(idx)) return false;

        // Continue down the tree
        btPhysAddr child_pa = table->GetChildAddr(idx);
        btVirtAddr child_va;
        if (! ptTranslatePAtoVA(child_pa, &child_va)) return false;
        table = MPFVTP_PT_TREE(child_va);
    }

    // Now at the leaf.  Add the translation.
    if (table->EntryExists(leaf_idx)) return false;

    table->InsertTranslatedAddr(leaf_idx, pa);
    return true;
}


bool
MPFVTP_PAGE_TABLE::AddPAtoVA(btPhysAddr pa, btVirtAddr va, uint32_t depth)
{
    MPFVTP_PT_TREE table = ptPtoV;

    // Index in the leaf page
    uint64_t leaf_idx = ptIdxFromAddr(uint64_t(pa), 4 - depth);

    uint32_t cur_depth = 4;
    while (--depth)
    {
        // Drop 4KB page offset
        uint64_t idx = ptIdxFromAddr(uint64_t(pa), --cur_depth);

        // Need a new page in the table?
        if (! table->EntryExists(idx))
        {
            // Add new page to the FPGA-visible virtual to physical table
            MPFVTP_PT_TREE child_table = new MPFVTP_PT_TREE_CLASS();
            if (child_table == NULL) return false;

            table->InsertChildAddr(idx, int64_t(child_table));
        }

        // Are we being asked to add an entry below a larger region that
        // is already mapped?
        if (table->EntryIsTerminal(idx)) return false;

        // Continue down the tree
        table = MPFVTP_PT_TREE(table->GetChildAddr(idx));
    }

    // Now at the leaf.  Add the translation.
    if (table->EntryExists(leaf_idx)) return false;

    table->InsertTranslatedAddr(leaf_idx, int64_t(va));
    return true;
}


void
MPFVTP_PAGE_TABLE::DumpPageTableVAtoPA(
    MPFVTP_PT_TREE table,
    uint64_t partial_va,
    uint32_t depth)
{
    for (uint64_t idx = 0; idx < 512; idx++)
    {
        if (table->EntryExists(idx))
        {
            uint64_t va = partial_va | (idx << (12 + 9 * (depth - 1)));
            if (table->EntryIsTerminal(idx))
            {
                // Found a translation
                const char *kind;
                switch (depth)
                {
                  case 1:
                    kind = "4KB";
                    break;
                  case 2:
                    kind = "2MB";
                    break;
                  default:
                    kind = "?";
                    break;
                }

                printf("    VA 0x%016lx -> PA 0x%016lx (%s)\n",
                       va,
                       table->GetTranslatedAddr(idx),
                       kind);

                // Validate translation function
                btPhysAddr check_pa;
                assert(ptTranslateVAtoPA(btVirtAddr(va), &check_pa));
                assert(check_pa == table->GetTranslatedAddr(idx));
            }
            else
            {
                // Follow pointer to another level
                assert(depth != 1);

                btPhysAddr child_pa = table->GetChildAddr(idx);
                btVirtAddr child_va;
                assert(ptTranslatePAtoVA(child_pa, &child_va));
                DumpPageTableVAtoPA(MPFVTP_PT_TREE(child_va), va, depth - 1);
            }
        }
    }
}


/// @} group VTPService

END_NAMESPACE(AAL)