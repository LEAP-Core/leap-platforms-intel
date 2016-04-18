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
// MPF -- Memory Properties Factory
//
//   This module implements the main pipeline that provides MPF services.
//   It should be instantiated by a module that defines the behavior
//   of the MPF edge that attaches to the FIU.  The pipeline here connects
//   the MPF FIU edge, MPF services and then to the AFU.
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
`include "cci_mpf_csrs.vh"
`include "cci_mpf_shim_edge.vh"

module cci_mpf_pipe_std
  #(
    // Maximum number of outstanding read and write requests per channel
    parameter MAX_ACTIVE_REQS = 128,

    //
    // See descriptions of these parameters in the cci_mpf module.
    //
    parameter MPF_INSTANCE_ID = 1,
    parameter DFH_MMIO_BASE_ADDR = 0,
    parameter DFH_MMIO_NEXT_ADDR = 0,
    parameter ENABLE_VTP = 1,
    parameter ENFORCE_WR_ORDER = 1,
    parameter SORT_READ_RESPONSES = 1,
    parameter PRESERVE_WRITE_MDATA = 0,
    parameter N_WRITE_HEAP_ENTRIES = 0
    )
   (
    input  logic      clk,

    // Signals connecting to QA Platform
    cci_mpf_if.to_fiu fiu,

    // Signals connecting to AFU, the client code
    cci_mpf_if.to_afu afu,

    // CSR connections
    cci_mpf_csrs mpf_csrs,

    // Connect MPF's AFU edge module to its FIU edge module
    cci_mpf_shim_edge_if.edge_afu edge_if
    );

    logic  reset;
    assign reset = fiu.reset;

    // ====================================================================
    //
    //  Stages here form a pipeline, transforming requests as they enter
    //  from the AFU through stages that compose to provide a complete
    //  memory subsystem.
    //
    //  The request (Tx) pipeline flows up from the bottom of the stages.
    //  The response (Rx) pipeline flows down from the top of the file.
    //
    // ====================================================================


    // ====================================================================
    //
    //  Detect the end of responses for a multi-beat packet (EOP).
    //  Single-beat responses will also be tagged EOP.
    //
    // ====================================================================

    cci_mpf_if stgp1_fiu_eop (.clk);

    cci_mpf_shim_detect_eop
      #(
        .MAX_ACTIVE_REQS(MAX_ACTIVE_REQS),
        .RESERVED_MDATA_IDX(CCI_PLATFORM_MDATA_WIDTH-2)
        )
      eop
       (
        .clk,
        .fiu,
        .afu(stgp1_fiu_eop)
        );


    // ====================================================================
    //
    //  Virtual to physical translation.
    //
    //  *** This stage may reorder requests relative to each other,
    //  *** including requests to the same line. Reordering occurs
    //  *** only on translation miss in order to allow hits to flow
    //  *** around misses.
    //  ***
    //  *** If strict ordering is required within cache lines then
    //  *** the write order shim (cci_mpf_shim_wro) must be closer
    //  *** to the AFU than this VTP stage.
    //
    // ====================================================================

    cci_mpf_if stgp2_fiu_virtual (.clk);

    generate
        if (ENABLE_VTP)
        begin : vtp
            cci_mpf_shim_vtp
              #(
                // VTP needs to generate loads internally in order to walk the
                // page table.  The reserved bit in Mdata is a location offered
                // to the page table walker to tag internal loads.  The Mdata
                // location is guaranteed to be zero on all requests flowing
                // in to VTP from the AFU.  In the composition here,
                // qa_shim_sort_responses provides this guarantee by rewriting
                // Mdata as requests and responses as they flow in and out
                // of the stack.
                .RESERVED_MDATA_IDX(CCI_PLATFORM_MDATA_WIDTH-2)
                )
              v_to_p
               (
                .clk,
                .fiu(stgp1_fiu_eop),
                .afu(stgp2_fiu_virtual),
                .csrs(mpf_csrs),
                .events(mpf_csrs)
                );
        end
        else
        begin : no_vtp
            cci_mpf_shim_null
              physical
               (
                .clk,
                .fiu(stgp1_fiu_eop),
                .afu(stgp2_fiu_virtual)
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Maintain read/write and write/write order to matching addresses.
    //  This level of the hierarchy operates on virtual addresses.
    //  Order preservation is optional, controlled by ENFORCE_WR_ORDER.
    //
    // ====================================================================

    cci_mpf_if stgp3_fiu_wro (.clk);

    generate
        if (ENFORCE_WR_ORDER)
        begin : wro
            cci_mpf_shim_wro
              order
               (
                .clk,
                .fiu(stgp2_fiu_virtual),
                .afu(stgp3_fiu_wro)
                );
        end
        else
        begin : no_wro
            cci_mpf_shim_null
              unordered
               (
                .clk,
                .fiu(stgp2_fiu_virtual),
                .afu(stgp3_fiu_wro)
                );
        end
    endgenerate


    // ====================================================================
    //
    //  Sort read responses so they arrive in the order they were
    //  requested.
    //
    //  Operates on virtual addresses.
    //
    //  *** In addition to sorting responses this stage preserves
    //  *** Mdata values for both read and write requests.  Mdata
    //  *** preservation is required early in the flow from the AFU.
    //  *** If no read response sorting is needed this module may
    //  *** still be used to preserve Mdata by setting the parameter
    //  *** SORT_READ_RESPONSES to 0.
    //
    // ====================================================================

    cci_mpf_if stgp4_fiu_rsp_order (.clk);

    cci_mpf_shim_rsp_order
      #(
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .PRESERVE_WRITE_MDATA(PRESERVE_WRITE_MDATA),
        .MAX_ACTIVE_REQS(MAX_ACTIVE_REQS)
        )
      rspOrder
       (
        .clk,
        .fiu(stgp3_fiu_wro),
        .afu(stgp4_fiu_rsp_order)
        );


    // ====================================================================
    //
    //  Register responses to AFU. The stage is inserted for timing.
    //
    // ====================================================================

    cci_mpf_if stgp5_mpf_afu (.clk);

    cci_mpf_shim_buffer_fiu
      regRsp
       (
        .clk,
        .fiu_raw(stgp4_fiu_rsp_order),
        .fiu_buf(stgp5_mpf_afu)
        );


    // ====================================================================
    //
    //  Mandatory MPF edge connection to the external AFU.
    //
    // ====================================================================

    cci_mpf_shim_edge_afu
      #(
        .N_WRITE_HEAP_ENTRIES(N_WRITE_HEAP_ENTRIES)
        )
      mpf_edge_afu
       (
        .clk,
        .afu_ext(afu),
        .afu(stgp5_mpf_afu),
        .fiu_edge(edge_if)
        );

endmodule // cci_mpf_pipe_std
