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
//

`include "cci_mpf_if.vh"

module qa_drv_memory
   (
    input  logic              clk,

    //
    // Signals connecting to QA Platform
    //
    cci_mpf_if.to_qlp         qlp,

    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    //
    // Memory read
    //
    input  t_cci_mpf_cl_vaddr mem_read_req_addr,
    // Use CCI's cache if true
    input  logic              mem_read_req_cached,
    // Enforce order of references to the same address?
    input  logic              mem_read_req_check_order,
    output logic              mem_read_req_rdy,
    input  logic              mem_read_req_enable,

    output t_cci_cldata       mem_read_rsp_data,
    output logic              mem_read_rsp_rdy,

    //
    // Memory write request
    //
    input  t_cci_mpf_cl_vaddr mem_write_addr,
    input  t_cci_cldata       mem_write_data,
    // Use CCI's cache if true
    input  logic              mem_write_req_cached,
    // Enforce order of references to the same address?
    input  logic              mem_write_req_check_order,
    output logic              mem_write_rdy,
    input  logic              mem_write_enable,

    // Write ACK count.  Pulse with a count every time writes completes.
    // Multiple writes may complete in a single cycle.
    output logic [1:0]        mem_write_ack
    );

    logic  reset_n;
    assign reset_n = qlp.reset_n;

    // ====================================================================
    //
    //   Map client memory interface to the MPF interface.
    //
    // ====================================================================

    cci_mpf_if#(.ENABLE_LOG(1)) afu_if(.clk);

    assign afu_if.c0Tx =
        genC0TxReadReqMPF(
            genReqHeaderMPF(mem_read_req_cached ? eREQ_RDLINE_S : eREQ_RDLINE_I,
                            mem_read_req_addr,
                            t_cci_mdata'(0),
                            mem_read_req_check_order),
            mem_read_req_enable);

    assign mem_read_req_rdy = ! afu_if.c0TxAlmFull;

    assign mem_read_rsp_data = afu_if.c0Rx.data;
    assign mem_read_rsp_rdy = afu_if.c0Rx.rdValid;

    assign afu_if.c1Tx =
        genC1TxWriteReqMPF(
            genReqHeaderMPF(mem_write_req_cached ? eREQ_WRLINE_M : eREQ_WRLINE_I,
                            mem_write_addr,
                            t_cci_mdata'(0),
                            mem_write_req_check_order),
            mem_write_data,
            mem_write_enable);

    assign mem_write_rdy = ! afu_if.c1TxAlmFull;

    assign mem_write_ack = 2'(afu_if.c0Rx.wrValid) +
                           2'(afu_if.c1Rx.wrValid);

    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            // Nothing
        end
        else
        begin
            assert(mem_read_req_rdy || ! mem_read_req_enable) else
                $fatal("qa_drv_memory: Memory read not ready!");
            assert(mem_write_rdy || ! mem_write_enable) else
                $fatal("qa_drv_memory: Memory write not ready!");
        end
    end


    // ====================================================================
    //
    //  Connect client requests to the QLP.
    //
    // ====================================================================

    cci_mpf
      #(
        .SORT_READ_RESPONSES(1),
        .PRESERVE_WRITE_MDATA(0)
        )
      mpf
       (
        .clk,
        .qlp(qlp),
        .afu(afu_if)
        );

endmodule
