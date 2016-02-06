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


//
// This is a mandatory connection at the head and tail of an MPF pipeline.
// It canonicalizes input and output and manages the flow of data through
// MPF.
//

module cci_mpf_shim_edge_connect
   (
    input  logic clk,

    // External connections to the FIU and AFU
    cci_mpf_if.to_fiu fiu_edge,
    cci_mpf_if.to_afu afu_edge,

    // Connection to the FIU end of the MPF pipeline
    cci_mpf_if.to_afu fiu,

    // Connection to the AFU end of the MPF pipeline
    cci_mpf_if.to_fiu afu
    );

    logic reset;
    assign reset = fiu_edge.reset;

    // Normal shims connect reset from FIU toward AFU.  This module has
    // two independent flows: the FIU edge and the AFU edge.  The MPF
    // pipeline will be the link between the two flows.  Hook up reset
    // independently.  The chain will be completed by the MPF pipeline.
    assign fiu.reset = fiu_edge.reset;
    assign afu_edge.reset = afu.reset;


    // ====================================================================
    //
    //   FIU edge flow
    //
    // ====================================================================

    assign fiu_edge.c0Tx = cci_mpf_updC0TxCanonical(fiu.c0Tx);
    assign fiu_edge.c1Tx = cci_mpf_updC1TxCanonical(fiu.c1Tx);
    assign fiu_edge.c2Tx = fiu.c2Tx;

    assign fiu.c0TxAlmFull = fiu_edge.c0TxAlmFull;
    assign fiu.c1TxAlmFull = fiu_edge.c1TxAlmFull;

    assign fiu.c0Rx = fiu_edge.c0Rx;
    assign fiu.c1Rx = fiu_edge.c1Rx;


    // ====================================================================
    //
    //   AFU edge flow
    //
    // ====================================================================

    assign afu.c0Tx = cci_mpf_updC0TxCanonical(afu_edge.c0Tx);
    assign afu.c1Tx = cci_mpf_updC1TxCanonical(afu_edge.c1Tx);
    assign afu.c2Tx = afu_edge.c2Tx;

    assign afu_edge.c0TxAlmFull = afu.c0TxAlmFull;
    assign afu_edge.c1TxAlmFull = afu.c1TxAlmFull;

    assign afu_edge.c0Rx = afu.c0Rx;
    assign afu_edge.c1Rx = afu.c1Rx;

    always_ff @(posedge clk)
    begin
        if (! reset)
        begin
            if (cci_mpf_c0TxIsReadReq(afu.c0Tx))
            begin
                assert(afu.c0Tx.hdr.base.cl_len == eCL_LEN_1) else
                    $fatal("cci_mpf_shim_edge_connect: Multi-beat reads not supported yet");
            end

            if (cci_mpf_c1TxIsWriteReq(afu.c1Tx))
            begin
                assert(afu.c1Tx.hdr.base.cl_len == eCL_LEN_1) else
                    $fatal("cci_mpf_shim_edge_connect: Multi-beat writes not supported yet");
            end
        end
    end

endmodule // cci_mpf_shim_edge_connect
