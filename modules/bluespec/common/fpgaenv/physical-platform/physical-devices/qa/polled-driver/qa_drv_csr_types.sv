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

`ifndef QA_DRV_CSR_TYPES
`define QA_DRV_CSR_TYPES

//
// FPGA-side control/status register definitions.
//

package qa_drv_csr_types;

    typedef enum logic [15:0]
    {
        //
        // CSR numbering must match the software-side numbering exactly!
        //
        CSR_AFU_DSM_BASEL          = 16'h1a00,
        CSR_AFU_DSM_BASEH          = 16'h1a04,
        CSR_AFU_CNTXT_BASEL        = 16'h1a08,
        CSR_AFU_CNTXT_BASEH        = 16'h1a0c,
        CSR_AFU_EN                 = 16'h1a10,

        CSR_AFU_READ_FRAME_BASEL   = 16'h1a18,
        CSR_AFU_READ_FRAME_BASEH   = 16'h1a1c,
        CSR_AFU_WRITE_FRAME_BASEL  = 16'h1a20,
        CSR_AFU_WRITE_FRAME_BASEH  = 16'h1a24,

        CSR_AFU_TRIGGER_DEBUG      = 16'h1a28,
        CSR_AFU_ENABLE_TEST        = 16'h1a2c
    }
    t_CSR_AFU_MAP;

    // Compare CSR address in a message header to the map above.  The CCI
    // header is 18 bits.
    function automatic csr_addr_matches;
        input [17:0] header;
        input t_CSR_AFU_MAP idx;
        begin
            // The address in the header is only 14 bits.  The low 2 bits are
            // dropped because addresses are 4-byte aligned.
            csr_addr_matches = (header[13:0] == idx[15:2]);
        end
    endfunction


    // CSR_AFU_TRIGGER_DEBUG passes a tag that may trigger writeback of
    // different debugging state.
    typedef logic [7:0] t_AFU_DEBUG_REQ;

    // CSR_AFU_ENABLE_TEST passes a tag that may trigger a test in the
    // driver.
    typedef logic [3:0] t_AFU_ENABLE_TEST;

    typedef struct
    {
        logic afu_dsm_base_valid;
        logic [63:0] afu_dsm_base;
        logic        afu_cntxt_base_valid;
        logic [63:0] afu_cntxt_base;
        logic        afu_en;

        logic [63:0] afu_write_frame;
        logic [63:0] afu_read_frame;

        // Debug request.  The manager will hold this
        // register for one cycle after a request is received and
        // then reset it to 0.
        t_AFU_DEBUG_REQ afu_trigger_debug;

        // Test request.  Held for one cycle, similar to afu_trigger_debug.
        t_AFU_ENABLE_TEST afu_enable_test;
    }
    t_CSR_AFU_STATE;

endpackage // qa_drv_csr_types

`endif //  `ifndef QA_DRV_CSR_TYPES
