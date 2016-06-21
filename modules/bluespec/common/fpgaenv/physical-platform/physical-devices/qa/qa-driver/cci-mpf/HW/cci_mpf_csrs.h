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
    CCI_MPF_VTP_CSR_MODE = 24,

    // Page table physical address (line address) (write)
    CCI_MPF_VTP_CSR_PAGE_TABLE_PADDR = 32,

    // Statistics -- all 8 byte read-only CSRs
    CCI_MPF_VTP_CSR_STAT_4KB_TLB_NUM_HITS = 40,
    CCI_MPF_VTP_CSR_STAT_4KB_TLB_NUM_MISSES = 48,
    CCI_MPF_VTP_CSR_STAT_2MB_TLB_NUM_HITS = 56,
    CCI_MPF_VTP_CSR_STAT_2MB_TLB_NUM_MISSES = 64,
    CCI_MPF_VTP_CSR_STAT_PT_WALK_BUSY_CYCLES = 72,
    CCI_MPF_VTP_CSR_STAT_FAILED_TRANSLATIONS = 80,

    // Must be last
    CCI_MPF_VTP_CSR_SIZE = 88
}
t_cci_mpf_vtp_csr_offsets;


//
// Read responses ordering feature -- {4c9c96f4-65ba-4dd8-b383-c70ace57bfe4}
//
typedef enum
{
    // MPF write/read order BBB feature header (read)
    CCI_MPF_RSP_ORDER_CSR_DFH = 0,
    // BBB feature ID low (read)
    CCI_MPF_RSP_ORDER_CSR_ID_L = 8,
    // BBB feature ID high (read)
    CCI_MPF_RSP_ORDER_CSR_ID_H = 16,

    // Must be last
    CCI_MPF_RSP_ORDER_CSR_SIZE = 24
}
t_cci_mpf_rsp_order_csr_offsets;


//
// Memory virtual channel mapping feature -- {5046c86f-ba48-4856-b8f9-3b76e3dd4e74}
//
typedef enum
{
    // MPF vc mapping BBB feature header (read)
    CCI_MPF_VC_MAP_CSR_DFH = 0,
    // BBB feature ID low (read)
    CCI_MPF_VC_MAP_CSR_ID_L = 8,
    // BBB feature ID high (read)
    CCI_MPF_VC_MAP_CSR_ID_H = 16,

    //
    // eVC_VA to physical channel mapping configuration.
    //
    // Groups are controlled individually.  The bits are read in a given
    // group only when the group enable bit is set in the high bits of
    // the CSR.
    //
    //  GROUP A:
    //
    //   Bit 0:
    //      Enable mapping when 1.  Default 1.
    //      Writing 0 will disable mapping and requests on eVC_VA will be
    //      forwarded to the FIU remaining on eVC_VA.
    //   Bit 1:
    //      Enable dynamic mapping.  Default 1.
    //      Dynamic mapping monitors traffic and adjusts the ratio of
    //      mapped channels to optimize throughput.  Optimal mapping
    //      varies depending on the ratio of reads to writes and the
    //      number of lines per request.
    //   Bits 5-2:
    //      Log2 of the dynamic sampling window size in cycles.  The
    //      dynamic mapper will consider changing only after 16
    //      consecutive windows suggest the same ratio.
    //
    //  GROUP B:
    //
    //   Bit 6:
    //      When 0: Only change the mapping on incoming requests to eVC_VA.
    //      When 1: Treat all incoming requests as though they were on eVC_VA.
    //              All requests will then be mapped using whatever policy
    //              is set for eVC_VA.
    //
    //  GROUP C:
    //
    //   Bit 7:
    //      When 0: Set mapping ratio to default for the platform.
    //      When 1: Use the ratio specifiers in bits 13-8.
    //   Bits 14-8:
    //      When bit 7 is 1 these are used to define the fraction of requests
    //      mapped to channel VL0.  The value is the number of 64ths that
    //      should be assigned VL0.  The remaining channel mappings are split
    //      evenly between VH0 and VH1.
    //
    //  GROUP D:
    //
    //   Bit 31-16:
    //      The traffic threshold in a sampling window below which all
    //      requests should be directed to the low latency VL0 port.  Low
    //      traffic does not need the bandwidth of multiple memory ports
    //      and may depend on low latency.  (E.g. pointer chasing)
    //
    //      The value here is the sum of all read and write lines requested
    //      in a sampling window.
    //
    //
    //  GROUP CONTROL:
    //
    //   Bit 60: Group D enable
    //   Bit 61: Group C enable
    //   Bit 62: Group B enable
    //   Bit 63: Group A enable
    //
    CCI_MPF_VC_MAP_CSR_CTRL_REG = 24,

    // Statistics -- all 8 byte read-only CSRs
    CCI_MPF_VC_MAP_CSR_STAT_NUM_MAPPING_CHANGES = 32,

    // Mapping history.  A vector of 8 bit values with the most recent state
    // in the low bits.  Each 8 bit value is the ratio of VL0 requests in
    // 64ths.
    CCI_MPF_VC_MAP_CSR_STAT_HISTORY = 40,

    // Must be last
    CCI_MPF_VC_MAP_CSR_SIZE = 48
}
t_cci_mpf_vc_map_csr_offsets;


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
