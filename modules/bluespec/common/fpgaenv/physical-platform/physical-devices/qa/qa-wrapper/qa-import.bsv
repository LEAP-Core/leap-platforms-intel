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

// This code wraps the QA CCI (coherent cache interface) in bluespec.

import Clocks::*;
import Vector::*;
import FIFO::*;
import FIFOF::*;

`include "awb/provides/umf.bsh"
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"


interface QA_DRIVER;
    method Action                   deq();
    method Bit#(SizeOf#(UMF_CHUNK)) first();
    method Bool                     notEmpty();
    method Action                   write(Bit#(SizeOf#(UMF_CHUNK)) chunk);
    method Bool                     notFull();
endinterface

interface QA_WIRES;
    (* prefix = "" *)
    method Action inputWires(Bit#(1)   vl_clk_LPdomain_16ui,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_SystemReset_n,
                             Bit#(18)  ffs_vl18_LP32ui_lp2sy_C0RxHdr,
                             Bit#(512) ffs_vl512_LP32ui_lp2sy_C0RxData,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0RxWrValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0RxRdValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0RxCgValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0RxUgValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0RxIrValid,
                             Bit#(18)  ffs_vl18_LP32ui_lp2sy_C1RxHdr,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C1RxWrValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C1RxIrValid,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C0TxAlmFull,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_C1TxAlmFull,
                             Bit#(1)   ffs_vl_LP32ui_lp2sy_InitDnForSys);

    (* prefix = "", always_ready *)
    method Bit#(61)  ffs_vl61_LP32ui_sy2lp_C0TxHdr;
    (* prefix = "", always_ready *)
    method Bit#(1)   ffs_vl_LP32ui_sy2lp_C0TxRdValid;
    (* prefix = "", always_ready *)
    method Bit#(61)  ffs_vl61_LP32ui_sy2lp_C1TxHdr;
    (* prefix = "", always_ready *)
    method Bit#(512) ffs_vl512_LP32ui_sy2lp_C1TxData;
    (* prefix = "", always_ready *)
    method Bit#(1)   ffs_vl_LP32ui_sy2lp_C1TxWrValid;
    (* prefix = "", always_ready *)
    method Bit#(1)   ffs_vl_LP32ui_sy2lp_C1TxIrValid;
endinterface

interface QA_DEVICE;
    interface QA_DRIVER driver; 
    interface QA_WIRES  wires;
endinterface

Integer umfChunkSize = valueOf(SizeOf#(UMF_CHUNK));

import "BVI" qa_driver = 
module mkQADeviceImport#(Clock vl_clk_LPdomain_32ui,
                         Reset ffs_vl_LP32ui_lp2sy_SoftReset_n)
    // Interface:
    (QA_DEVICE);

    parameter TXHDR_WIDTH = `CCI_TXHDR_WIDTH;
    parameter RXHDR_WIDTH = `CCI_RXHDR_WIDTH;
    parameter CACHE_WIDTH = `CCI_CACHE_WIDTH;
    parameter UMF_WIDTH   = umfChunkSize;

    input_clock (vl_clk_LPdomain_32ui) = vl_clk_LPdomain_32ui;
    default_clock vl_clk_LPdomain_32ui;

    input_reset (ffs_vl_LP32ui_lp2sy_SoftReset_n) = ffs_vl_LP32ui_lp2sy_SoftReset_n;
    default_reset ffs_vl_LP32ui_lp2sy_SoftReset_n;

    interface QA_DRIVER driver;
        method deq() ready(rx_fifo_rdy) enable(rx_fifo_enable);
        method rx_fifo_data first() ready(rx_fifo_rdy);
        method rx_fifo_rdy notEmpty();
        method write(tx_fifo_data) ready(tx_fifo_rdy) enable(tx_fifo_enable);
        method tx_fifo_rdy notFull();
    endinterface

    interface QA_WIRES wires;
        method inputWires(vl_clk_LPdomain_16ui,
                          ffs_vl_LP32ui_lp2sy_SystemReset_n,
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
                          ffs_vl_LP32ui_lp2sy_C0TxAlmFull,
                          ffs_vl_LP32ui_lp2sy_C1TxAlmFull,
                          ffs_vl_LP32ui_lp2sy_InitDnForSys)
            enable((*inhigh*) EN) clocked_by(no_clock);

        method ffs_vl61_LP32ui_sy2lp_C0TxHdr ffs_vl61_LP32ui_sy2lp_C0TxHdr() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C0TxRdValid ffs_vl_LP32ui_sy2lp_C0TxRdValid() clocked_by(no_clock);
        method ffs_vl61_LP32ui_sy2lp_C1TxHdr ffs_vl61_LP32ui_sy2lp_C1TxHdr() clocked_by(no_clock);
        method ffs_vl512_LP32ui_sy2lp_C1TxData ffs_vl512_LP32ui_sy2lp_C1TxData() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C1TxWrValid ffs_vl_LP32ui_sy2lp_C1TxWrValid() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C1TxIrValid ffs_vl_LP32ui_sy2lp_C1TxIrValid() clocked_by(no_clock);
    endinterface

    schedule (driver_deq) C (driver_deq);
    schedule (driver_deq) CF (driver_first, driver_write, driver_notEmpty, driver_notFull);
    schedule (driver_first) CF (driver_deq, driver_first, driver_write, driver_notEmpty, driver_notFull);
    schedule (driver_write) C (driver_write);    
    schedule (driver_write) CF (driver_deq, driver_first, driver_notEmpty, driver_notFull);
    schedule (driver_notFull, driver_notEmpty) CF (driver_deq, driver_first, driver_write, driver_notEmpty, driver_notFull);

    schedule (wires_inputWires,
              wires_ffs_vl61_LP32ui_sy2lp_C0TxHdr,
              wires_ffs_vl_LP32ui_sy2lp_C0TxRdValid,
              wires_ffs_vl61_LP32ui_sy2lp_C1TxHdr,
              wires_ffs_vl512_LP32ui_sy2lp_C1TxData,
              wires_ffs_vl_LP32ui_sy2lp_C1TxWrValid,
              wires_ffs_vl_LP32ui_sy2lp_C1TxIrValid)
             CF
             (wires_inputWires,
              wires_ffs_vl61_LP32ui_sy2lp_C0TxHdr,
              wires_ffs_vl_LP32ui_sy2lp_C0TxRdValid,
              wires_ffs_vl61_LP32ui_sy2lp_C1TxHdr,
              wires_ffs_vl512_LP32ui_sy2lp_C1TxData,
              wires_ffs_vl_LP32ui_sy2lp_C1TxWrValid,
              wires_ffs_vl_LP32ui_sy2lp_C1TxIrValid,
              driver_deq, driver_first, driver_write, driver_notFull);
endmodule


module [CONNECTED_MODULE] mkQADevice#(Clock vl_clk_LPdomain_32ui,
                                      Reset ffs_vl_LP32ui_lp2sy_SoftReset_n,
                                      SOFT_RESET_TRIGGER softResetTrigger)
    // Interface:
    (QA_DEVICE);

    let qa_clock = vl_clk_LPdomain_32ui;
    let qa_reset = ffs_vl_LP32ui_lp2sy_SoftReset_n;

    // FIFOs for coming out of QA domain.

    let qaDevice <- mkQADeviceImport(vl_clk_LPdomain_32ui,
                                     ffs_vl_LP32ui_lp2sy_SoftReset_n);
    let qa_driver = qaDevice.driver;

    SyncFIFOIfc#(UMF_CHUNK) syncReadQ <- mkSyncFIFOToCC(16, qa_clock, qa_reset);
    SyncFIFOIfc#(UMF_CHUNK) syncWriteQ <- mkSyncFIFOFromCC(16, qa_clock);

    rule pullDataIn;
        syncReadQ.enq(qa_driver.first);
        qa_driver.deq;
    endrule

    rule pushDataOut;
        qa_driver.write(syncWriteQ.first);
        syncWriteQ.deq;
    endrule

    interface QA_DRIVER driver;
        method deq = syncReadQ.deq;
        method first = syncReadQ.first;
        method notEmpty = syncReadQ.notEmpty;
        method write = syncWriteQ.enq;
        method notFull = syncWriteQ.notFull;
    endinterface

    interface QA_WIRES wires = qaDevice.wires;
endmodule
