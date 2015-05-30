//
// Copyright (c) 2014, Intel Corporation
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

//
// Takes all the wires from the QuickAssist CCI interface and builds
// a driver that implements a LEAP physical channel.  A read/write interface
// to the physical channel is also exposed in the qa_wrapper interface.
//

module qa_wrapper#(parameter TXHDR_WIDTH=61, RXHDR_WIDTH=18, CACHE_WIDTH=512, UMF_WIDTH=128)
(
    // ------------------- LEAP Facing Interface --------------------------
    // RX side
    rx_data,
    rx_rdy,
    rx_enable,

    // TX side
    tx_data,
    tx_rdy,
    tx_enable,

    // ------------------- Intel QuickAssist Interface --------------------
    vl_clk_LPdomain_32ui,
    vl_clk_LPdomain_16ui,
    ffs_vl_LP32ui_lp2sy_SystemReset_n,
    ffs_vl_LP32ui_lp2sy_SoftReset_n,

    ffs_vl18_LP32ui_lp2sy_C0RxHdr,
    ffs_vl512_LP32ui_lp2sy_C0RxData,
    ffs_vl_LP32ui_lp2sy_C0RxWrValid,
    ffs_vl_LP32ui_lp2sy_C0RxRdValid,
    ffs_vl_LP32ui_lp2sy_C0RxCgValid,
    ffs_vl_LP32ui_lp2sy_C0RxUgValid,
    ffs_vl_LP32ui_lp2sy_C0RxIrValid,

    ffs_vl18_LP32ui_lp2sy_C1RxHdr,
    ffs_vl_LP32ui_lp2sy_C1RxWrValid,
    ffs_vl_LP32ui_lp2sy_C1RxIrValid,

    ffs_vl61_LP32ui_sy2lp_C0TxHdr,
    ffs_vl_LP32ui_sy2lp_C0TxRdValid,

    ffs_vl61_LP32ui_sy2lp_C1TxHdr,
    ffs_vl512_LP32ui_sy2lp_C1TxData,
    ffs_vl_LP32ui_sy2lp_C1TxWrValid,
    ffs_vl_LP32ui_sy2lp_C1TxIrValid,

    ffs_vl_LP32ui_lp2sy_C0TxAlmFull,
    ffs_vl_LP32ui_lp2sy_C1TxAlmFull,

    ffs_vl_LP32ui_lp2sy_InitDnForSys
);

    // LEAP facing interface
    output [UMF_WIDTH-1:0]    rx_data;   
    output                    rx_rdy;
    input                     rx_enable;

    // TX side
    input [UMF_WIDTH-1:0]     tx_data;
    output                    tx_rdy;
    input                     tx_enable;

    // Intel QuickAssist interface
    input           vl_clk_LPdomain_32ui;
    input           vl_clk_LPdomain_16ui;
    input           ffs_vl_LP32ui_lp2sy_SystemReset_n;
    input           ffs_vl_LP32ui_lp2sy_SoftReset_n;

    input   [17:0]  ffs_vl18_LP32ui_lp2sy_C0RxHdr;
    input   [511:0] ffs_vl512_LP32ui_lp2sy_C0RxData;
    input           ffs_vl_LP32ui_lp2sy_C0RxWrValid;
    input           ffs_vl_LP32ui_lp2sy_C0RxRdValid;
    input           ffs_vl_LP32ui_lp2sy_C0RxCgValid;
    input           ffs_vl_LP32ui_lp2sy_C0RxUgValid;
    input           ffs_vl_LP32ui_lp2sy_C0RxIrValid;

    input    [17:0] ffs_vl18_LP32ui_lp2sy_C1RxHdr;
    input           ffs_vl_LP32ui_lp2sy_C1RxWrValid;
    input           ffs_vl_LP32ui_lp2sy_C1RxIrValid;

    output   [60:0] ffs_vl61_LP32ui_sy2lp_C0TxHdr;
    output          ffs_vl_LP32ui_sy2lp_C0TxRdValid;

    output   [60:0] ffs_vl61_LP32ui_sy2lp_C1TxHdr;
    output  [511:0] ffs_vl512_LP32ui_sy2lp_C1TxData;
    output          ffs_vl_LP32ui_sy2lp_C1TxWrValid;
    output          ffs_vl_LP32ui_sy2lp_C1TxIrValid;

    input           ffs_vl_LP32ui_lp2sy_C0TxAlmFull;
    input           ffs_vl_LP32ui_lp2sy_C1TxAlmFull;

    input           ffs_vl_LP32ui_lp2sy_InitDnForSys;


    //
    // The QuickAssist specification demands that all outputs be registered.
    // We guarantee that here.
    //
    reg      [60:0] reg_ffs_vl61_LP32ui_sy2lp_C0TxHdr;
    reg             reg_ffs_vl_LP32ui_sy2lp_C0TxRdValid;

    reg      [60:0] reg_ffs_vl61_LP32ui_sy2lp_C1TxHdr;
    reg     [511:0] reg_ffs_vl512_LP32ui_sy2lp_C1TxData;
    reg             reg_ffs_vl_LP32ui_sy2lp_C1TxWrValid;
    reg             reg_ffs_vl_LP32ui_sy2lp_C1TxIrValid;

    wire     [60:0] next_ffs_vl61_LP32ui_sy2lp_C0TxHdr;
    wire            next_ffs_vl_LP32ui_sy2lp_C0TxRdValid;

    wire     [60:0] next_ffs_vl61_LP32ui_sy2lp_C1TxHdr;
    wire    [511:0] next_ffs_vl512_LP32ui_sy2lp_C1TxData;
    wire            next_ffs_vl_LP32ui_sy2lp_C1TxWrValid;
    wire            next_ffs_vl_LP32ui_sy2lp_C1TxIrValid;

    // Forward registered requests to the platform.
    assign ffs_vl61_LP32ui_sy2lp_C0TxHdr = reg_ffs_vl61_LP32ui_sy2lp_C0TxHdr;
    assign ffs_vl_LP32ui_sy2lp_C0TxRdValid = reg_ffs_vl_LP32ui_sy2lp_C0TxRdValid;

    assign ffs_vl61_LP32ui_sy2lp_C1TxHdr = reg_ffs_vl61_LP32ui_sy2lp_C1TxHdr;
    assign ffs_vl512_LP32ui_sy2lp_C1TxData = reg_ffs_vl512_LP32ui_sy2lp_C1TxData;
    assign ffs_vl_LP32ui_sy2lp_C1TxWrValid = reg_ffs_vl_LP32ui_sy2lp_C1TxWrValid;
    assign ffs_vl_LP32ui_sy2lp_C1TxIrValid = reg_ffs_vl_LP32ui_sy2lp_C1TxIrValid;

    // Forward our driver's requests to the request registers.
    always @(posedge vl_clk_LPdomain_32ui)
    begin
        if (! ffs_vl_LP32ui_lp2sy_SystemReset_n)
        begin
            reg_ffs_vl_LP32ui_sy2lp_C0TxRdValid <= 0;
            reg_ffs_vl_LP32ui_sy2lp_C1TxWrValid <= 0;
            reg_ffs_vl_LP32ui_sy2lp_C1TxIrValid <= 0;
        end
        else
        begin
            reg_ffs_vl61_LP32ui_sy2lp_C0TxHdr = next_ffs_vl61_LP32ui_sy2lp_C0TxHdr;
            reg_ffs_vl_LP32ui_sy2lp_C0TxRdValid = next_ffs_vl_LP32ui_sy2lp_C0TxRdValid;

            reg_ffs_vl61_LP32ui_sy2lp_C1TxHdr = next_ffs_vl61_LP32ui_sy2lp_C1TxHdr;
            reg_ffs_vl512_LP32ui_sy2lp_C1TxData = next_ffs_vl512_LP32ui_sy2lp_C1TxData;
            reg_ffs_vl_LP32ui_sy2lp_C1TxWrValid = next_ffs_vl_LP32ui_sy2lp_C1TxWrValid;
            // Note: we don't use C1TxIrValid
        end
    end


    //
    // Instantiate our driver.  Note that the driver's requests to the platform
    // are written to registers and forwarded in the next cycle, above.
    //
    qa_driver driver(
        .clk(vl_clk_LPdomain_32ui),
        .resetb(ffs_vl_LP32ui_lp2sy_SoftReset_n),
        .rx_c0_header(ffs_vl18_LP32ui_lp2sy_C0RxHdr),
        .rx_c0_data(ffs_vl512_LP32ui_lp2sy_C0RxData),
        .rx_c0_wrvalid(ffs_vl_LP32ui_lp2sy_C0RxWrValid),
        .rx_c0_rdvalid(ffs_vl_LP32ui_lp2sy_C0RxRdValid),
        .rx_c0_cfgvalid(ffs_vl_LP32ui_lp2sy_C0RxCgValid),
        //    rb2cf_C0RxUMsgValid
        //    rb2cf_C0RxIntrValid
        .rx_c1_header(ffs_vl18_LP32ui_lp2sy_C1RxHdr),
        .rx_c1_wrvalid(ffs_vl_LP32ui_lp2sy_C1RxWrValid),
        //    rb2cf_C1RxIntrValid

        .tx_c0_header(next_ffs_vl61_LP32ui_sy2lp_C0TxHdr),
        .tx_c0_rdvalid(next_ffs_vl_LP32ui_sy2lp_C0TxRdValid),
        .tx_c1_header(next_ffs_vl61_LP32ui_sy2lp_C1TxHdr),
        .tx_c1_data(next_ffs_vl512_LP32ui_sy2lp_C1TxData),
        .tx_c1_wrvalid(next_ffs_vl_LP32ui_sy2lp_C1TxWrValid),
        //    cf2ci_C1TxIntrValid
        .tx_c0_almostfull(ffs_vl_LP32ui_lp2sy_C0TxAlmFull),
        .tx_c1_almostfull(ffs_vl_LP32ui_lp2sy_C1TxAlmFull),

        .lp_initdone(ffs_vl_LP32ui_lp2sy_InitDnForSys),

        .rx_data(rx_data),
        .rx_rdy(rx_rdy),
        .rx_enable(rx_enable),

        // TX side
        .tx_data(tx_data),
        .tx_rdy(tx_rdy),
        .tx_enable(tx_enable)
    );
endmodule

