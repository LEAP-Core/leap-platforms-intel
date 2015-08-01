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
    // Mdata tag sent in CCI requests and returned with CCI responses.
    //
    typedef logic [12:0] t_MDATA;

    //
    // CCI-S interface
    //
    typedef logic [31:0] t_LINE_ADDR_CCI_S;

    typedef struct packed
    {
        logic [4:0]   rsvd2;
        t_TX_REQUEST  requestType;
        logic [5:0]   rsvd1;
        logic [31:0]  address;
        logic         rsvd0;
        t_MDATA       mdata;
    }
    t_TX_HEADER_CCI_S;

    function automatic t_TX_HEADER_CCI_S genReqHeaderCCIS;
        input t_TX_REQUEST      requestType;
        input t_LINE_ADDR_CCI_S address;
        input t_MDATA           mdata;

        t_TX_HEADER_CCI_S h;

        h.requestType = requestType;
        h.address = address[31:0];
        h.mdata = mdata;

        h.rsvd2 = 0;
        h.rsvd1 = 0;
        h.rsvd0 = 0;

        genReqHeaderCCIS = h;
    endfunction


    //
    // CCI-E interface
    //
    typedef logic [57:0] t_LINE_ADDR_CCI_E;

    typedef struct packed
    {
        logic [5:0]   rsvd4;
        logic [25:0]  hAddress;
        logic         atype;
        logic [4:0]   rsvd3;
        logic [4:0]   rsvd2;
        t_TX_REQUEST  requestType;
        logic [5:0]   rsvd1;
        logic [31:0]  address;
        logic         rsvd0;
        t_MDATA       mdata;
    }
    t_TX_HEADER_CCI_E;

    function automatic t_TX_HEADER_CCI_E genReqHeaderCCIE;
        input t_TX_REQUEST      requestType;
        input t_LINE_ADDR_CCI_E address;
        input t_MDATA           mdata;

        t_TX_HEADER_CCI_E h;

        h.atype = 1'b1;
        h.requestType = requestType;

        h.hAddress = address[57:32];
        h.address = address[31:0];

        h.mdata = mdata;

        h.rsvd4 = 0;
        h.rsvd3 = 0;
        h.rsvd2 = 0;
        h.rsvd1 = 0;
        h.rsvd0 = 0;

        genReqHeaderCCIE = h;
    endfunction

endpackage // qa_driver_types

`endif
