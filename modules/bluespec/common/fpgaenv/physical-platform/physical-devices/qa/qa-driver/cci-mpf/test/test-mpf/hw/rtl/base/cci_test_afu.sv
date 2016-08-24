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

`include "cci_mpf_platform.vh"
`include "cci_test_csrs.vh"

import ccip_if_pkg::*;

module ccip_std_afu
   (
    // CCI-P Clocks and Resets
    input           logic             pClk,              // 400MHz - CCI-P clock domain. Primary interface clock
    input           logic             pClkDiv2,          // 200MHz - CCI-P clock domain.
    input           logic             pClkDiv4,          // 100MHz - CCI-P clock domain.
    input           logic             uClk_usr,          // User clock domain. Refer to clock programming guide  ** Currently provides fixed 300MHz clock **
    input           logic             uClk_usrDiv2,      // User clock domain. Half the programmed frequency  ** Currently provides fixed 150MHz clock **
    input           logic             pck_cp2af_softReset,      // CCI-P ACTIVE HIGH Soft Reset
    input           logic [1:0]       pck_cp2af_pwrState,       // CCI-P AFU Power State
    input           logic             pck_cp2af_error,          // CCI-P Protocol Error Detected

    // Interface structures
    input           t_if_ccip_Rx      pck_cp2af_sRx,        // CCI-P Rx Port
    output          t_if_ccip_Tx      pck_af2cp_sTx         // CCI-P Tx Port
    );


    //
    // Select the clock that will drive the AFU.
    //
    localparam AFU_CLOCK_FREQ = `AFU_CLOCK_FREQ;
    logic afu_clk;
    logic afu_reset;

    generate
        if (AFU_CLOCK_FREQ == 400)
            assign afu_clk = pClk;
        else if (AFU_CLOCK_FREQ == 300)
            assign afu_clk = uClk_usr;
        else if (AFU_CLOCK_FREQ == 200)
            assign afu_clk = pClkDiv2;
        else if (AFU_CLOCK_FREQ == 150)
            assign afu_clk = uClk_usrDiv2;
        else if (AFU_CLOCK_FREQ == 100)
            assign afu_clk = pClkDiv4;
        else
        begin
            always_ff @(posedge pClk)
            begin
                $fatal("Unsupported platform clock frequency: %d", AFU_CLOCK_FREQ);
            end
        end
    endgenerate

    t_if_ccip_Rx afck_cp2af_sRx;
    t_if_ccip_Tx afck_af2cp_sTx;

    //
    // Clock crossing FIFO to connect the fast CCI-P interface to the
    // slower AFU.
    //
    generate
        if (AFU_CLOCK_FREQ == 400)
        begin : nc
            assign afu_reset = pck_cp2af_softReset;
            assign afck_cp2af_sRx = pck_cp2af_sRx;
            assign pck_af2cp_sTx = afck_af2cp_sTx;
        end
        else
        begin : c
            ccip_async_shim
              afu_clock_crossing
                (
                 // Blue bitstream interface (pClk)
                 .bb_softreset(pck_cp2af_softReset),
                 .bb_clk(pClk),
                 .bb_rx(pck_cp2af_sRx),
                 .bb_tx(pck_af2cp_sTx),

                 // AFU
                 .afu_softreset(afu_reset),
                 .afu_clk(afu_clk),
                 .afu_rx(afck_cp2af_sRx),
                 .afu_tx(afck_af2cp_sTx)
                 );
        end
    endgenerate


    // ====================================================================
    //
    //  Convert the external wires to an MPF interface.
    //
    // ====================================================================

    //
    // The AFU exposes the primary AFU device feature header (DFH) at MMIO
    // address 0.  MPF defines a set of its own DFHs.  The AFU must
    // build its feature chain to point to the MPF chain.  The AFU must
    // also tell the MPF module the MMIO address at which MPF should start
    // its feature chain.
    //
    localparam MPF_DFH_MMIO_ADDR = 'h1000;

    //
    // MPF represents CCI as a SystemVerilog interface, derived from the
    // same basic types defined in ccip_if_pkg.  Interfaces reduce the
    // number of internal MPF module parameters, since each internal MPF
    // shim has a bus connected toward the AFU and a bus connected toward
    // the FIU.
    //

    //
    // Expose FIU as an MPF interface
    //
    cci_mpf_if#(.ENABLE_LOG(1)) fiu(.clk(afu_clk));

    // The CCI wires to MPF mapping connections have identical naming to
    // the standard AFU.  The module exports an interface named "fiu".
    ccip_wires_to_mpf
      #(
        // All inputs and outputs in PR region (AFU) must be registered!
        .REGISTER_INPUTS(1),
        .REGISTER_OUTPUTS(1)
        )
      map_ifc
       (
        .pClk(afu_clk),
        .pck_cp2af_softReset(afu_reset),
        .pck_cp2af_sRx(afck_cp2af_sRx),
        .pck_af2cp_sTx(afck_af2cp_sTx),
        .*
        );


    // ====================================================================
    //
    //  Manage CSRs at the lowest level so they can observe the edge state
    //  and to keep them available even when other code fails.
    //
    // ====================================================================

    cci_mpf_if afu_csrs(.clk(afu_clk));
    test_csrs csrs();

    cci_test_csrs
      #(
        .NEXT_DFH_BYTE_OFFSET(MPF_DFH_MMIO_ADDR)
        )
      csr_io
       (
        .clk(afu_clk),
        .fiu,
        .afu(afu_csrs),
        .csrs
        );


    // ====================================================================
    //
    //  Instantiate a memory properties factory (MPF) between the external
    //  interface and the AFU, adding support for virtual memory and
    //  control over memory ordering.
    //
    // ====================================================================

    cci_mpf_if#(.ENABLE_LOG(1)) afu(.clk(afu_clk));

    cci_mpf
      #(
        // Should read responses be returned in the same order that
        // the reads were requested?
        .SORT_READ_RESPONSES(1),

        // Should the Mdata from write requests be returned in write
        // responses?  If the AFU is simply counting write responses
        // and isn't consuming Mdata, then setting this to 0 eliminates
        // the memory and logic inside MPF for preserving Mdata.
        .PRESERVE_WRITE_MDATA(1),

        // Enable virtual to physical translation?  When enabled, MPF
        // accepts requests with either virtual or physical addresses.
        // Virtual addresses are indicated by setting the
        // addrIsVirtual flag in the MPF extended Tx channel
        // request header.
        .ENABLE_VTP(1),

        // Enable mapping of eVC_VA to physical channels?  AFUs that both use
        // eVC_VA and read back memory locations written by the AFU must either
        // emit WrFence on VA or use explicit physical channels and enforce
        // write/read order.  Each method has tradeoffs.  WrFence VA is expensive
        // and should be emitted only infrequently.  Memory requests to eVC_VA
        // may have higher bandwidth than explicit mapping.  The MPF module for
        // physical channel mapping is optimized for each CCI platform.
        //
        // If you set ENFORCE_WR_ORDER below you probably also want to set
        // ENABLE_VC_MAP.
        //
        // The mapVAtoPhysChannel extended header bit must be set on each
        // request to enable mapping.
        .ENABLE_VC_MAP(1),
        // When ENABLE_VC_MAP is set the mapping is either static for the entire
        // run or dynamic, changing in response to traffic patterns.  The mapper
        // guarantees synchronization when the mapping changes by emitting a
        // WrFence on eVC_VA and draining all reads.  Ignored when ENABLE_VC_MAP
        // is 0.
        .ENABLE_DYNAMIC_VC_MAPPING(1),

        // Should write/write and write/read ordering within a cache
        // be enforced?  By default CCI makes no guarantees on the order
        // in which operations to the same cache line return.  Setting
        // this to 1 adds logic to filter reads and writes to ensure
        // that writes retire in order and the reads correspond to the
        // most recent write.
        //
        // ***  Even when set to 1, MPF guarantees order only within
        // ***  a given virtual channel.  There is no guarantee of
        // ***  order across virtual channels and no guarantee when
        // ***  using eVC_VA, since it spreads requests across all
        // ***  channels.  Synchronizing writes across virtual channels
        // ***  can be accomplished only by requesting a write fence on
        // ***  eVC_VA.  Syncronizing writes across virtual channels
        // ***  and then reading back the same data requires both
        // ***  requesting a write fence on eVC_VA and waiting for the
        // ***  corresponding write fence response.
        //
        .ENFORCE_WR_ORDER(1),

        // Enable partial write emulation.  CCI has no support for masked
        // writes that merge new data with existing data in a line.  MPF
        // adds byte-level masks to the write request header and emulates
        // partial writes as a read-modify-write operation.  When coupled
        // with ENFORCE_WR_ORDER, partial writes are free of races on the
        // FPGA side.  There are no guarantees of atomicity and there is
        // no protection against races with CPU-generates writes.
        .ENABLE_PARTIAL_WRITES(1),

        // Address of the MPF feature header.  See comment above.
        .DFH_MMIO_BASE_ADDR(MPF_DFH_MMIO_ADDR)
        )
      mpf
       (
        .clk(afu_clk),
        .fiu(afu_csrs),
        .afu
        );


    // ====================================================================
    //
    //  Instantiate the test.
    //
    // ====================================================================

    test_afu
      test
       (
        .clk(afu_clk),
        .fiu(afu),
        .csrs
        );

endmodule
