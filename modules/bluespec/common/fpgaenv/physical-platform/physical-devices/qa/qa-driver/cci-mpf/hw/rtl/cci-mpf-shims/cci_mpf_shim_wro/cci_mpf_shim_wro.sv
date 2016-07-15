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

`include "cci_mpf_if.vh"


//
// Guarantee that writes to the same address complete in order and that reads
// to addresses matching writes complete in order relative to the write.
//


module cci_mpf_shim_wro
  #(
    parameter AFU_BUF_THRESHOLD = CCI_TX_ALMOST_FULL_THRESHOLD
    )
   (
    input  logic clk,

    // Connection toward the QA platform.  Reset comes in here.
    cci_mpf_if.to_fiu fiu,

    // Connections toward user code.
    cci_mpf_if.to_afu afu
    );

    logic reset = 1'b1;
    always @(posedge clk)
    begin
        reset <= fiu.reset;
    end

    logic c1_notEmpty;

    //
    // Writes use a decode filter so are less expensive than read entries
    //
`ifdef MPF_PLATFORM_BDX
    localparam N_C0_CAM_IDX_ENTRIES = 80;
    localparam N_C1_CAM_IDX_ENTRIES = 128;
    localparam ADDRESS_HASH_BITS = 9;
`elsif MPF_PLATFORM_OME
    localparam N_C0_CAM_IDX_ENTRIES = 80;
    localparam N_C1_CAM_IDX_ENTRIES = 128;
    localparam ADDRESS_HASH_BITS = 9;
`else
    ** ERROR: Unknown platform
`endif

    cci_mpf_shim_wro_cam_group
      #(
        .N_C0_CAM_IDX_ENTRIES(N_C0_CAM_IDX_ENTRIES),
        .N_C1_CAM_IDX_ENTRIES(N_C1_CAM_IDX_ENTRIES),
        .ADDRESS_HASH_BITS(ADDRESS_HASH_BITS),
        .AFU_BUF_THRESHOLD(AFU_BUF_THRESHOLD)
        )
      pipe
       (
        .clk,
        .fiu,
        .afu,
        .c1_notEmpty
        );

endmodule // cci_mpf_shim_wro
