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


// ========================================================================
//
//  This file is included by both C++ and System Verilog.  The syntax
//  must be acceptable to both.
//
// ========================================================================

//
// CSR offsets from the host channel CSR base address.
//
typedef enum
{
    // Enable I/O through the host channel
    CSR_HC_EN                 = 0,

    // CSR for setting base (physical) address host channel control frame
    CSR_HC_CTRL_FRAME         = 8,

    // CSR for setting base address of the host to FPGA buffer
    CSR_HC_READ_FRAME         = 16,

    // CSR for setting base address of the FPGA to host buffer
    CSR_HC_WRITE_FRAME        = 24,

    // Set testing mode
    CSR_HC_ENABLE_TEST        = 32,

    // END OF HOST CHANNEL CSR RANGE
    CSR_HC_LAST               = 48
}
t_qa_host_channel_csr_offsets;
