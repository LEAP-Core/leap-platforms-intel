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

package qa_drv_hc_csr_types;
    import cci_mpf_if_pkg::t_cci_claddr;

    // CSR_HC_ENABLE_TEST passes a tag that may trigger a test in the
    // driver.
    typedef struct packed
    {
        // Count of messages to send for SOURCE mode test.
        logic [29:0] count;
        // Test -- must match t_STATE in qa_drv_tester.
        logic [1:0]  test_state;
    }
    t_hc_enable_test;

    typedef struct
    {
        // Enable driver
        logic        hc_en;
        // Enable channel I/O connection to user code
        logic        hc_en_user_channel;

        t_cci_claddr hc_ctrl_frame;
        logic hc_ctrl_frame_valid;

        t_cci_claddr hc_write_frame;
        t_cci_claddr hc_read_frame;

        // Test request.  The manager will hold the idx field in this
        // register for one cycle after a request is received and
        // then reset it to 0.
        t_hc_enable_test hc_enable_test;
    }
    t_qa_drv_hc_csrs;

endpackage // qa_drv_hc_csr_types
