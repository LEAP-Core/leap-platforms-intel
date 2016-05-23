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

`include "cci_mpf_if.vh"
`include "cci_mpf_csrs.vh"

`include "cci_mpf_prim_hash.vh"


//
// Map read/write requests to eVC_VA to specific physical channels.  Mapping
// is a function of addresses such that a read or write to a given location
// is always mapped to the same channel.  This makes it possible to be sure
// that a value written is committed to memory before a later read or write.
// This method of tracking write responses works only within a single channel.
// Cross-channel commits require WrFence to eVC_VA, which is expensive.
//
// Throughput using eVC_VA is typically higher than throughput using explicit
// channel mapping.  This module seeks to optimize the ratio of requests
// for maximum throughput on a given hardware platform.
//


module cci_mpf_shim_vc_map
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu,

    cci_mpf_csrs.vc_map csrs
    );

    assign afu.reset = fiu.reset;

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end


    // Pass-through
    always_comb
    begin
        fiu.c2Tx = afu.c2Tx;

        afu.c0TxAlmFull = fiu.c0TxAlmFull;
        afu.c1TxAlmFull = fiu.c1TxAlmFull;

        afu.c0Rx = fiu.c0Rx;
        afu.c1Rx = fiu.c1Rx;
    end


    //
    // Control mapping
    //
    logic mapping_disabled;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            mapping_disabled <= 1'b0;
        end
        else if (csrs.vc_map_ctrl_valid)
        begin
            mapping_disabled <= ~ csrs.vc_map_ctrl[0];
        end
    end


    //
    // Request mapping function.  The mapping is consistent for a given address.
    //
    function automatic t_ccip_vc mapVA(t_ccip_clAddr addr);
        t_ccip_vc vc;

        // The hash function operates on 32 bits of the address.  Drop the
        // low address bits that are covered by multi-line requests so that
        // a given address always winds up hashed to the same channel,
        // independent of the access size.
        logic [31:0] a = addr[$bits(t_ccip_clNum) +: 32];

        // Input bits 4 and 5 are underrepresented in the low 6 bits of
        // the CRC-32 hash.  Swap them with less important higher bits
        // of the address.
        logic [31:0] addr_swizzle = { a[29:4], a[31:30], a[3:0] };

        // Hash addresses for even distribution within the mapping table,
        // attempting to have the mapping be independent of the memory
        // access pattern.
        logic [5:0] hashed_idx = 6'(hash32(addr_swizzle));

        // Map in a ratio 2 VL0 : 3 VH0 : 3 VH1, which appears to be optimal
        // for CCI-P on BDX.  The order of entries is unimportant since
        // indices are hashed.
        unique case (hashed_idx) inside
            [6'd0  : 6'd15]: vc = eVC_VL0;
            [6'd16 : 6'd39]: vc = eVC_VH0;
            [6'd40 : 6'd63]: vc = eVC_VH1;
        endcase

        return vc;
    endfunction


    always_comb
    begin
        fiu.c0Tx = afu.c0Tx;

        if (! mapping_disabled &&
            cci_mpf_c0_getReqMapVA(afu.c0Tx.hdr) &&
            (afu.c0Tx.hdr.base.vc_sel == eVC_VA))
        begin
            fiu.c0Tx.hdr.base.vc_sel = mapVA(cci_mpf_c0_getReqAddr(afu.c0Tx.hdr));
        end
    end

    always_comb
    begin
        fiu.c1Tx = afu.c1Tx;

        if (! mapping_disabled &&
            cci_mpf_c1_getReqMapVA(afu.c1Tx.hdr) &&
            (afu.c1Tx.hdr.base.vc_sel == eVC_VA))
        begin
            fiu.c1Tx.hdr.base.vc_sel = mapVA(cci_mpf_c1_getReqAddr(afu.c1Tx.hdr));
        end
    end


endmodule // cci_mpf_shim_vc_map
