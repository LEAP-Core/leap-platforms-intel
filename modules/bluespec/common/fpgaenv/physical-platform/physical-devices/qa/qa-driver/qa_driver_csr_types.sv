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

    // QA driver MMIO feature space size (bytes)
    parameter QA_DRIVER_DFH_SIZE = 16'h1b00;

    //
    // These CSRs are used only in the old CCI-S mode.  When possible,
    // MMIO and feature lists are used instead.
    //
    typedef enum logic [15:0]
    {
        //
        // CSR numbering must match the software-side numbering exactly!
        //
        CSR_AFU_DSM_BASE           = 16'h1a00,

        // LEAP status register
        CSR_AFU_SREG_READ          = 16'h1a10,

        // MMIO read compatibility for CCI-S.  Writes here are treated
        // as a CSR read request.
        CSR_AFU_MMIO_READ_COMPAT   = 16'h1a14
    }
    t_ccis_csr_afu_map;

    
    // LEAP status registers, exposed as a debugging interface to read status
    // from the FPGA-side client.
    typedef logic [31:0] t_sreg_addr;
    typedef logic [63:0] t_sreg;

    // Compare CSR address in a message header to the map above.  The CCI
    // header is 18 bits.
    function automatic logic csrAddrMatches(
        input t_if_cci_c0_Rx req,
        input t_ccis_csr_afu_map idx
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
        t_sreg_addr afu_sreg_addr;
    }
    t_csr_afu_state;

endpackage // qa_driver_csr_types
