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


//
// This wrapper is a reference implementation of the composition of shims.
// Developers are free to compose memories with other properties.
//

module cci_mpf
  #(
    // MMIO base address (byte level) allocated to MPF for feature lists
    // and CSRs.  The AFU allocating this module must build at least
    // a device feature header (DFH) for the AFU.  The chain of device
    // features in the AFU must then point to the base address here
    // as another feature in the chain.  MPF will continue the list.
    // The base address here must point to a region that is at least
    // CCI_MPF_MMIO_SIZE bytes.
    parameter DFH_MMIO_BASE_ADDR = 0,

    // Address of the next device feature header outside MPF.  MPF will
    // terminate the feature list if the next address is 0.
    parameter DFH_MMIO_NEXT_ADDR = 0,

    // Enforce write/write and write/read ordering with cache lines?
    parameter ENFORCE_WR_ORDER = 1,

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
    cci_mpf_if.to_fiu fiu,

    //
    // Signals connecting to AFU, the client code
    //
    cci_mpf_if.to_afu afu
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
    //  Canonicalize requests on exit toward the FIU. This stage must be
    //  inserted at both ends of the pipeline.
    //
    // ====================================================================

    cci_mpf_if stg1_fiu_canonical (.clk);

    cci_mpf_shim_canonicalize_to_fiu
      canonicalize_out
       (
        .clk,
        .fiu,
        .afu(stg1_fiu_canonical)
        );


    // ====================================================================
    //
    //  Manage CSRs used by MPF
    //
    // ====================================================================

    cci_mpf_if stg2_fiu_csrs (.clk);
    cci_mpf_csrs mpf_csrs ();

    cci_mpf_shim_csr
      #(
        .DFH_MMIO_BASE_ADDR(DFH_MMIO_BASE_ADDR),
        .DFH_MMIO_NEXT_ADDR(DFH_MMIO_NEXT_ADDR),
        .MPF_ENABLE_VTP(1),
        .MPF_ENABLE_WRO(1)
        )
      csr
       (
        .clk,
        .fiu(stg1_fiu_canonical),
        .afu(stg2_fiu_csrs),
        .csrs(mpf_csrs)
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

    cci_mpf_if stg3_fiu_virtual (.clk);

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
        .fiu(stg2_fiu_csrs),
        .afu(stg3_fiu_virtual),
        .csrs(mpf_csrs)
        );


    // ====================================================================
    //
    //  Maintain read/write and write/write order to matching addresses.
    //  This level of the hierarchy operates on virtual addresses.
    //  Order preservation is optional, controlled by ENFORCE_WR_ORDER.
    //
    // ====================================================================

    cci_mpf_if stg4_fiu_wro (.clk);

    generate
        if (ENFORCE_WR_ORDER)
        begin : wro
            cci_mpf_shim_wro
              order
               (
                .clk,
                .fiu(stg3_fiu_virtual),
                .afu(stg4_fiu_wro)
                );
        end
        else
        begin : no_wro
            cci_mpf_shim_null
              filter
               (
                .clk,
                .fiu(stg3_fiu_virtual),
                .afu(stg4_fiu_wro)
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

    cci_mpf_if stg5_fiu_rsp_order (.clk);

    cci_mpf_shim_rsp_order
      #(
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .PRESERVE_WRITE_MDATA(PRESERVE_WRITE_MDATA)
        )
      rspOrder
       (
        .clk,
        .fiu(stg4_fiu_wro),
        .afu(stg5_fiu_rsp_order)
        );


    // ====================================================================
    //
    //  Register responses to AFU. The stage is inserted for timing.
    //
    // ====================================================================

    cci_mpf_if stg6_fiu_reg_rsp (.clk);

    cci_mpf_shim_buffer_fiu
      regRsp
       (
        .clk,
        .fiu_raw(stg5_fiu_rsp_order),
        .fiu_buf(stg6_fiu_reg_rsp)
        );


    // ====================================================================
    //
    //  Canonicalize requests on entry from the AFU. This stage must be
    //  inserted at both ends of the pipeline.
    //
    // ====================================================================

    cci_mpf_shim_canonicalize_to_fiu
      canonicalize_in
       (
        .clk,
        .fiu(stg6_fiu_reg_rsp),
        .afu(afu)
        );

endmodule // cci_mpf
