//
// Copyright (c) 2015, Intel Corporation
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
// FPGA-side control/status register definitions.
//

package qa_driver_csr_types;
    import cci_mpf_if_pkg::*;
    import cci_csr_if_pkg::*;

    typedef enum logic [15:0]
    {
        //
        // CSR numbering must match the software-side numbering exactly!
        //
        CSR_AFU_DSM_BASEL          = 16'h1a00,
        CSR_AFU_DSM_BASEH          = 16'h1a04,
        CSR_AFU_CNTXT_BASEL        = 16'h1a08,
        CSR_AFU_CNTXT_BASEH        = 16'h1a0c,

        // LEAP status register
        CSR_AFU_SREG_READ          = 16'h1a10,

        // MMIO read compatibility for CCI-S.  Writes here are treated
        // as a CSR read request.
        CSR_AFU_MMIO_READ_COMPAT   = 16'h1a14,

        // Page table base for qa_shim_tlb_simple (64 bits)
        CSR_AFU_PAGE_TABLE_BASEL   = 16'h1a80,
        CSR_AFU_PAGE_TABLE_BASEH   = 16'h1a84
    }
    t_CSR_AFU_MAP;

    
    // LEAP status registers, exposed as a debugging interface to read status
    // from the FPGA-side client.
    typedef logic [31:0] t_sreg_addr;
    typedef logic [63:0] t_sreg;

    typedef struct
    {
        logic enable;
        t_sreg_addr addr;
    }
    t_afu_sreg_req;


    // Compare CSR address in a message header to the map above.  The CCI
    // header is 18 bits.
    function automatic logic csrAddrMatches(
        input t_if_cci_c0_Rx req,
        input t_CSR_AFU_MAP idx
        );

        t_cci_mmioaddr req_addr = cci_csr_getAddress(req);

        // The low 2 bits of the address are dropped because addresses
        // are 4-byte aligned.
        return (req_addr == t_cci_mmioaddr'(idx >> 2));
    endfunction

    typedef struct
    {
        logic afu_dsm_base_valid;
        logic [63:0] afu_dsm_base;

        // Client status register read request.  Enable is held for one cycle.
        t_afu_sreg_req afu_sreg_req;
    }
    t_csr_afu_state;

endpackage // qa_driver_csr_types
