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

`include "qa_driver.vh"

module qa_drv_memory
  #(
    parameter CCI_ADDR_WIDTH = 32,
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13
    )
   (
    input  logic                 clk,

    //
    // Signals connecting to QA Platform
    //
    qlp_interface.to_qlp         qlp,

    // -------------------------------------------------------------------
    //
    //   Client interface
    //
    // -------------------------------------------------------------------

    //
    // Memory read
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_read_req_addr,
    output logic                      mem_read_req_rdy,
    input  logic                      mem_read_req_enable,

    output logic [CCI_DATA_WIDTH-1:0] mem_read_rsp_data,
    output logic                      mem_read_rsp_rdy,

    //
    // Memory write request
    //
    input  logic [CCI_ADDR_WIDTH-1:0] mem_write_addr,
    input  logic [CCI_DATA_WIDTH-1:0] mem_write_data,
    output logic                      mem_write_rdy,
    input  logic                      mem_write_enable,

    // Write ACK count.  Pulse with a count every time writes completes.
    // Multiple writes may complete in a single cycle.
    output logic [1:0]                mem_write_ack
    );

    logic  resetb;
    assign resetb = qlp.resetb;

    typedef logic [CCI_TX_HDR_WIDTH-1:0] t_TX_HEADER;

    // ====================================================================
    //
    //  Sort read responses so they arrive in order.
    //
    // ====================================================================

    qlp_interface
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      qlp_inorder (.clk);

    qa_shim_sort_responses
      #(
        .CCI_DATA_WIDTH(CCI_DATA_WIDTH),
        .CCI_RX_HDR_WIDTH(CCI_RX_HDR_WIDTH),
        .CCI_TX_HDR_WIDTH(CCI_TX_HDR_WIDTH),
        .CCI_TAG_WIDTH(CCI_TAG_WIDTH)
        )
      sorter
       (
        .clk,
        .qlp,
        .afu(qlp_inorder)
        );


    // ====================================================================
    //
    //  Connect client requests to the QLP.
    //
    // ====================================================================

    //
    // The CCI-S and CCI-E headers share a base set of fields.  Construct
    // a CCI-E header and truncate to the requested size, which may be CCI-S.
    assign qlp_inorder.C0TxHdr =
        t_TX_HEADER'(genReqHeaderCCIE(RdLine,
                                      t_LINE_ADDR_CCI_E'(mem_read_req_addr),
                                      t_MDATA'(0)));
    assign qlp_inorder.C0TxRdValid = mem_read_req_enable;
    assign mem_read_req_rdy = ! qlp_inorder.C0TxAlmFull;

    assign mem_read_rsp_data = qlp_inorder.C0RxData;
    assign mem_read_rsp_rdy = qlp_inorder.C0RxRdValid;

    assign qlp_inorder.C1TxHdr =
        t_TX_HEADER'(genReqHeaderCCIE(WrLine,
                                      t_LINE_ADDR_CCI_E'(mem_write_addr),
                                      t_MDATA'(0)));
    assign qlp_inorder.C1TxData = mem_write_data;
    assign mem_write_rdy = ! qlp_inorder.C1TxAlmFull;
    assign qlp_inorder.C1TxWrValid = mem_write_enable;
    assign qlp_inorder.C1TxIrValid = 1'b0;

    assign mem_write_ack = 2'(qlp_inorder.C0RxWrValid) +
                           2'(qlp_inorder.C1RxWrValid);

    always_ff @(posedge clk)
    begin
        if (! resetb)
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

endmodule
