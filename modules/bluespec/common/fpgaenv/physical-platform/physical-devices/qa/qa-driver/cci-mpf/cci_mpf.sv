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
// MPF -- Memory Protocol Factory
//
//   The factory is a composable collection of shims for constructing
//   Xeon+FPGA memory interfaces with a variety of characteristics.
//
//   Shims offer features such as:
//     - Sort read responses to match request order
//     - Virtual to physical translation (VTP)
//     - Preserve read/write and write/write ordering within lines.
//

`include "cci_mpf_if.vh"


//
// This wrapper is a reference implementation of the composition of shims.
//

module cci_mpf
  #(
    // Return read responses in the order they were requested?
    parameter SORT_READ_RESPONSES = 1,

    // Preserve Mdata field in write requests?  Turn this off if the AFU
    // merely counts write responses instead of checking Mdata.
    parameter PRESERVE_WRITE_MDATA = 0
    )
   (
    input  logic      clk,

    //
    // Signals connecting to QA Platform
    //
    cci_mpf_if.to_qlp qlp,

    //
    // Signals connecting to AFU, the client code
    //
    cci_mpf_if.to_afu afu
    );

    logic  reset_n;
    assign reset_n = qlp.reset_n;

    // ====================================================================
    //
    //  Virtual to physical translation. This is the lowest level of
    //  the hierarchy, nearest the QLP connection. The translation layer
    //  can thus depend on a few properties, such as that only one
    //  request is outstanding to a given line. The virtual to physical
    //  translator is thus free to reorder any requests.
    //
    // ====================================================================

    cci_mpf_if qlp_virtual (.clk);

    cci_mpf_shim_vtp
      #(
        // VTP needs to generate loads internally in order to walk the
        // page table.  The reserved bit in Mdata is a location offered
        // to the page table walker to tag internal loads.  The Mdata location
        // is guaranteed to be zero on all requests flowing in to VTP
        // from the AFU.  In the composition here, qa_shim_sort_responses
        // provides this guarantee by rewriting Mdata as requests and
        // responses as they flow in and out of the stack.
        .RESERVED_MDATA_IDX(CCI_MDATA_WIDTH-2)
        )
      v_to_p
       (
        .clk,
        .qlp,
        .afu(qlp_virtual)
        );


    // ====================================================================
    //
    //  Maintain read/write and write/write order to matching addresses.
    //  This level of the hierarchy operates on virtual addresses.
    //
    // ====================================================================

    cci_mpf_if qlp_write_order (.clk);

    cci_mpf_shim_write_order
      filter
       (
        .clk,
        .qlp(qlp_virtual),
        .afu(qlp_write_order)
        );


    // ====================================================================
    //
    //  Sort read responses so they arrive in the order they were
    //  requested.
    //
    //  Operates on virtual addresses.
    //
    // ====================================================================

    cci_mpf_shim_rsp_order
      #(
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .PRESERVE_WRITE_MDATA(PRESERVE_WRITE_MDATA)
        )
      rspOrder
       (
        .clk,
        .qlp(qlp_write_order),
        .afu(afu)
        );

endmodule // cci_mpf

