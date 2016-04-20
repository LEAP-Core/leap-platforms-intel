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
// MPF main wrapper.  This module defines the edge of MPF that attaches
// to the FIU.  It then instantiates an MPF pipeline to implement the
// desired MPF services.
//

`include "cci_mpf_if.vh"
`include "cci_mpf_csrs.vh"
`include "cci_mpf_shim_edge.vh"


//
// This wrapper is a reference implementation of the composition of shims.
// Developers are free to compose memories with other properties.
//

module cci_mpf
  #(
    // Instance ID reported in feature IDs of all device feature
    // headers instantiated under this instance of MPF.  If only a single
    // MPF instance is instantiated in the AFU then leaving the instance
    // ID at 1 is probably the right choice.
    parameter MPF_INSTANCE_ID = 1,

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

    // Enable virtual to physical translation?
    parameter ENABLE_VTP = 1,

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

    // Maximum number of outstanding read and write requests per channel
    localparam MAX_ACTIVE_REQS = 128;

    logic  reset;
    assign reset = fiu.reset;


    // ====================================================================
    //
    //  Mandatory MPF edge connection to both the external AFU and FIU
    //  links and to both ends of the MPF pipeline defined in this module.
    //
    // ====================================================================

    cci_mpf_if stgm1_mpf_fiu (.clk);

    // Number of unique write request packets that may be active in MPF.
    // Multi-flit packets count as one entry. Packets become active when
    // a TX request arrives from the AFU and are inactivated as the TX
    // request exits MPF toward the FIU.
    localparam N_WRITE_HEAP_ENTRIES = 128;

    cci_mpf_shim_edge_if
      #(
        .N_WRITE_HEAP_ENTRIES(N_WRITE_HEAP_ENTRIES)
        )
      edge_if();

    cci_mpf_shim_vtp_pt_walk_if pt_walk();

    cci_mpf_shim_edge_fiu
      #(
        .N_WRITE_HEAP_ENTRIES(N_WRITE_HEAP_ENTRIES),

        // VTP needs to generate loads internally in order to walk the
        // page table.  The reserved bit in Mdata is a location offered
        // to the page table walker to tag internal loads.  The Mdata
        // location is guaranteed to be zero on all requests flowing
        // in to VTP from the AFU.
        .VTP_PT_RESERVED_MDATA_IDX(CCI_PLATFORM_MDATA_WIDTH-2)
        )
      mpf_edge_fiu
       (
        .clk,
        .fiu_ext(fiu),
        .fiu(stgm1_mpf_fiu),
        .afu_edge(edge_if),
        .pt_walk
        );


    // ====================================================================
    //
    //  Manage CSRs used by MPF
    //
    // ====================================================================

    cci_mpf_if stgm2_fiu_csrs (.clk);
    cci_mpf_csrs mpf_csrs ();

    cci_mpf_shim_csr
      #(
        .MPF_INSTANCE_ID(MPF_INSTANCE_ID),
        .DFH_MMIO_BASE_ADDR(DFH_MMIO_BASE_ADDR),
        .DFH_MMIO_NEXT_ADDR(DFH_MMIO_NEXT_ADDR),
        .MPF_ENABLE_VTP(ENABLE_VTP),
        .MPF_ENABLE_WRO(ENFORCE_WR_ORDER)
        )
      csr
       (
        .clk,
        .fiu(stgm1_mpf_fiu),
        .afu(stgm2_fiu_csrs),
        .csrs(mpf_csrs),
        .events(mpf_csrs)
        );


    // ====================================================================
    //
    //  Instantiate an MPF pipeline composed of the desired shims
    //
    // ====================================================================

    cci_mpf_pipe_std
      #(
        .MAX_ACTIVE_REQS(MAX_ACTIVE_REQS),
        .MPF_INSTANCE_ID(MPF_INSTANCE_ID),
        .DFH_MMIO_BASE_ADDR(DFH_MMIO_BASE_ADDR),
        .DFH_MMIO_NEXT_ADDR(DFH_MMIO_NEXT_ADDR),
        .ENABLE_VTP(ENABLE_VTP),
        .ENFORCE_WR_ORDER(ENFORCE_WR_ORDER),
        .SORT_READ_RESPONSES(SORT_READ_RESPONSES),
        .PRESERVE_WRITE_MDATA(PRESERVE_WRITE_MDATA),
        .N_WRITE_HEAP_ENTRIES(N_WRITE_HEAP_ENTRIES)
        )
      mpf_pipe
       (
        .clk,
        .fiu(stgm2_fiu_csrs),
        .afu,
        .mpf_csrs,
        .edge_if,
        .pt_walk_walker(pt_walk),
        .pt_walk_client(pt_walk)
        );

endmodule // cci_mpf
