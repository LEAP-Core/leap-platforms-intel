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

`ifndef QA_DRIVER_TYPES
`define QA_DRIVER_TYPES

//
// Main type definitions for the QA driver.
//

package qa_driver_types;
    import qa_driver_csr_types::*;

    //
    // General parameters
    //
    typedef enum
    {
        // Number of requests that can be accepted after almost full
        // is asserted.
        ALM_FULL_THRESHOLD = 4
    }
    t_QA_DRIVER_PARAMS;


    //
    // Requested operation.
    //
    typedef enum logic [3:0]
    {
        WrThru   = 4'h1,
        WrLine   = 4'h2,
        WrFence  = 4'h5,
        RdLine   = 4'h4,
        RdLine_I = 4'h6
    }
    t_TX_REQUEST;

    //
    // Response type.
    //
    typedef enum logic [3:0]
    {
        WrLineRsp = 4'h1,
        RdLineRsp = 4'h4
    }
    t_RX_RESPONSE;

endpackage // qa_driver_types

`endif
