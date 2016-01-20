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

//
// CSR address offsets in MPF shims.
//
//   This file is included in both C and Verilog code and must be
//   syntactically correct in both.
//

//
// VTP feature -- {c8a2982f-ff96-42bf-a705-45727f501901}
//
typedef enum
{
    // VTP BBB feature header (read)
    CCI_MPF_VTP_CSR_DFH = 0,
    // BBB feature ID low (read)
    CCI_MPF_VTP_CSR_ID_L = 8,
    // BBB feature ID high (read)
    CCI_MPF_VTP_CSR_ID_H = 16,

    // Mode (4 bytes) (read/write)
    //   Bit 0:
    //      0 - Disabled (block memory traffic)
    //      1 - Enabled
    //   Bit 1:
    //      0 - Normal
    //      1 - Invalidate current FPGA-side translation cache.
    //          Bit 0 must be 0 to disable translation during flush.
    //          Software may also read this register.  Bit 1 in the
    //          register will return 1 during invalidation and 0 when
    //          invalidation is complete.
    CCI_MPF_VTP_CSR_MODE = 24,

    // Page table physical address (line address) (write)
    CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR = 32,

    // Statistics -- all 8 byte read-only CSRs
    CCI_MPF_VTP_CSR_STAT_NUM_HITS = 40,
    CCI_MPF_VTP_CSR_STAT_NUM_MISSES = 48,

    // Must be last
    CCI_MPF_VTP_CSR_SIZE = 56
}
t_cci_mpf_vtp_csr_offsets;


//
// Write ordering feature -- {56b06b48-9dd7-4004-a47e-0681b4207a6d}
//
typedef enum
{
    // MPF write/read order BBB feature header (read)
    CCI_MPF_WRO_CSR_DFH = 0,
    // BBB feature ID low (read)
    CCI_MPF_WRO_CSR_ID_L = 8,
    // BBB feature ID high (read)
    CCI_MPF_WRO_CSR_ID_H = 16,

    // Statistics -- all 8 byte read-only

    //   Total writes observed
    CCI_MPF_WRO_CSR_NUM_WR = 24,
    //   Total reads observed
    CCI_MPF_WRO_CSR_NUM_RD = 32,
    //   Total conflicting (blocked) writes
    CCI_MPF_WRO_CSR_NUM_WR_CONFLICTS = 40,
    //   Total conflicting (blocked) reads
    CCI_MPF_WRO_CSR_NUM_RD_CONFLICTS = 48,

    // Must be last
    CCI_MPF_WRO_CSR_SIZE = 56
}
t_cci_mpf_wro_csr_offsets;
