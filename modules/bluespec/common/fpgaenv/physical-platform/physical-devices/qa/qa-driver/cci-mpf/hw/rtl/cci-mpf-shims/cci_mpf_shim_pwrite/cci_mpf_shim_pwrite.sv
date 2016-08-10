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
`include "cci_mpf_shim_pwrite.vh"

//
// Partial write emulation using read-modify-write.  This module does not
// guarantee atomic access to the updated line.  On the FPGA side it relies
// on the WRO shim for managing read/write access to a line during an update.
// Conflicting CPU updates are not detected.
//

module cci_mpf_shim_pwrite
  #(
    parameter N_WRITE_HEAP_ENTRIES = 0
    )
   (
    input  logic clk,

    // Connection toward the FIU (the end of the MPF pipeline nearest the AFU)
    cci_mpf_if.to_fiu fiu,

    // External connections to the AFU
    cci_mpf_if.to_afu afu,

    // Interface to the MPF FIU edge module
    cci_mpf_shim_pwrite_if.pwrite pwrite,

    cci_mpf_csrs.pwrite_events events
    );

    logic reset;
    assign reset = fiu.reset;
    assign afu.reset = fiu.reset;

    assign afu.c0TxAlmFull = fiu.c0TxAlmFull;
    assign afu.c1TxAlmFull = fiu.c1TxAlmFull;

    assign fiu.c0Tx = afu.c0Tx;
    assign fiu.c1Tx = afu.c1Tx;
    assign fiu.c2Tx = afu.c2Tx;

    assign afu.c0Rx = fiu.c0Rx;
    assign afu.c1Rx = fiu.c1Rx;

    assign events.pwrite_out_event_pwrite = fiu.c1Tx.hdr.pwrite.isPartialWrite &&
                                            cci_mpf_c1TxIsValid(fiu.c1Tx);

endmodule // cci_mpf_shim_pwrite
