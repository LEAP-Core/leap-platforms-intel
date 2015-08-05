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

`ifndef CCI_LOOPBACK_HACK_Z
import GetPut::*;
import Connectable::*;
`endif


`include "awb/provides/umf.bsh"
`include "awb/provides/physical_platform_utils.bsh"

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/clocks_device.bsh"

// Maximum outstanding memory requests
typedef 64 QA_MAX_MEM_READS;

// Maximum outstanding memory requests.  Allow many writes since the overhead
// here is low.  (Just a counter.)
typedef 256 QA_MAX_MEM_WRITES;

typedef Bit#(32) QA_SREG_ADDR;
typedef Bit#(64) QA_SREG;

typedef Bit#(`CCI_ADDR_WIDTH) QA_CCI_ADDR;
typedef Bit#(`CCI_DATA_WIDTH) QA_CCI_DATA;

interface QA_CHANNEL_DRIVER;
    method Action                     deq();
    method Bit#(SizeOf#(UMF_CHUNK))   first();
    method Bool                       notEmpty();
    method Action                     write(Bit#(SizeOf#(UMF_CHUNK)) chunk);
    method Bool                       notFull();
endinterface

interface QA_MEMORY_DRIVER#(numeric type n_WRITE_ACK_BITS);
    method Action readLineReq(QA_CCI_ADDR addr);
    method ActionValue#(QA_CCI_DATA) readLineRsp();

    method Action writeLine(QA_CCI_ADDR addr,
                            QA_CCI_DATA data);

    // True if any writes are still in flight
    method ActionValue#(Bit#(n_WRITE_ACK_BITS)) writeAck();
endinterface

// Status register read request from the host.  Useful mostly for
// debugging.
interface QA_SREG_DRIVER;
    method ActionValue#(QA_SREG_ADDR) sregReq();
    method Action                     sregRsp(QA_SREG val);
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

interface QA_DEVICE#(numeric type n_WRITE_ACK_BITS);
    interface QA_CHANNEL_DRIVER                   channelDriver; 
    interface QA_MEMORY_DRIVER#(n_WRITE_ACK_BITS) memoryDriver;
    interface QA_SREG_DRIVER                      sregDriver; 
    (* prefix = "" *)
    interface QA_WIRES                            wires;
endinterface

// Import version of the interface with 2-bit memory write ACK.
typedef QA_DEVICE#(2) QA_DEVICE_IMPORT;

// Bluespec platform version of the interface with 4-bit memory write ACK in
// order to cope with latency-insensitivity and slower clocks.
typedef 4 QA_DEVICE_WRITE_ACK_BITS;
typedef QA_DEVICE#(QA_DEVICE_WRITE_ACK_BITS) QA_DEVICE_PLAT;


Integer umfChunkSize = valueOf(SizeOf#(UMF_CHUNK));

import "BVI" qa_driver = 
module mkQADeviceImport#(Clock vl_clk_LPdomain_32ui,
                         Reset ffs_vl_LP32ui_lp2sy_SoftReset_n)
    // Interface:
    (QA_DEVICE_IMPORT);

    parameter CCI_ADDR_WIDTH   = `CCI_ADDR_WIDTH;
    parameter CCI_DATA_WIDTH   = `CCI_DATA_WIDTH;
    parameter CCI_RX_HDR_WIDTH = `CCI_RXHDR_WIDTH;
    parameter CCI_TX_HDR_WIDTH = `CCI_TXHDR_WIDTH;
    parameter UMF_WIDTH        = umfChunkSize;

    input_clock (vl_clk_LPdomain_32ui) = vl_clk_LPdomain_32ui;
    default_clock vl_clk_LPdomain_32ui;

    input_reset (ffs_vl_LP32ui_lp2sy_SoftReset_n) = ffs_vl_LP32ui_lp2sy_SoftReset_n;
    default_reset ffs_vl_LP32ui_lp2sy_SoftReset_n;

    interface QA_CHANNEL_DRIVER channelDriver;
        method deq() ready(rx_fifo_rdy) enable(rx_fifo_enable);
        method rx_fifo_data first() ready(rx_fifo_rdy);
        method rx_fifo_rdy notEmpty();
        method write(tx_fifo_data) ready(tx_fifo_rdy) enable(tx_fifo_enable);
        method tx_fifo_rdy notFull();
    endinterface

    interface QA_MEMORY_DRIVER memoryDriver;
        method readLineReq(mem_read_req_addr) ready(mem_read_req_rdy) enable(mem_read_req_enable);
        method mem_read_rsp_data readLineRsp() ready(mem_read_rsp_rdy) enable((*inhigh*) en0);

        method writeLine(mem_write_addr, mem_write_data) ready(mem_write_rdy) enable(mem_write_enable);
        method mem_write_ack writeAck() enable((*inhigh*) en1);
    endinterface

    interface QA_SREG_DRIVER sregDriver; 
        method sreg_req_addr sregReq() ready(sreg_req_rdy) enable((*inhigh*) en2);
        method sregRsp(sreg_rsp) enable(sreg_rsp_enable);
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
            enable((*inhigh*) EN);

        method ffs_vl61_LP32ui_sy2lp_C0TxHdr ffs_vl61_LP32ui_sy2lp_C0TxHdr() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C0TxRdValid ffs_vl_LP32ui_sy2lp_C0TxRdValid() clocked_by(no_clock);
        method ffs_vl61_LP32ui_sy2lp_C1TxHdr ffs_vl61_LP32ui_sy2lp_C1TxHdr() clocked_by(no_clock);
        method ffs_vl512_LP32ui_sy2lp_C1TxData ffs_vl512_LP32ui_sy2lp_C1TxData() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C1TxWrValid ffs_vl_LP32ui_sy2lp_C1TxWrValid() clocked_by(no_clock);
        method ffs_vl_LP32ui_sy2lp_C1TxIrValid ffs_vl_LP32ui_sy2lp_C1TxIrValid() clocked_by(no_clock);
    endinterface

    schedule (channelDriver_deq) C (channelDriver_deq);
    schedule (channelDriver_deq) CF (channelDriver_first, channelDriver_write, channelDriver_notEmpty, channelDriver_notFull, sregDriver_sregReq, sregDriver_sregRsp);
    schedule (channelDriver_first) CF (channelDriver_deq, channelDriver_first, channelDriver_write, channelDriver_notEmpty, channelDriver_notFull, memoryDriver_writeAck, sregDriver_sregReq, sregDriver_sregRsp);
    schedule (channelDriver_write) C (channelDriver_write);    
    schedule (channelDriver_write) CF (channelDriver_deq, channelDriver_first, channelDriver_notEmpty, channelDriver_notFull, sregDriver_sregReq, sregDriver_sregRsp);
    schedule (channelDriver_notFull, channelDriver_notEmpty) CF (channelDriver_deq, channelDriver_first, channelDriver_write, channelDriver_notEmpty, channelDriver_notFull, memoryDriver_writeAck, sregDriver_sregReq, sregDriver_sregRsp);

    schedule (memoryDriver_readLineReq) C (memoryDriver_readLineReq);
    schedule (memoryDriver_readLineReq) CF (memoryDriver_readLineRsp, memoryDriver_writeLine, memoryDriver_writeAck);
    schedule (memoryDriver_readLineRsp) C (memoryDriver_readLineRsp);
    schedule (memoryDriver_readLineRsp) CF (memoryDriver_readLineReq, memoryDriver_writeLine, memoryDriver_writeAck);
    schedule (memoryDriver_writeLine) C (memoryDriver_writeLine);
    schedule (memoryDriver_writeLine) CF (memoryDriver_readLineReq, memoryDriver_readLineRsp, memoryDriver_writeAck);
    schedule (memoryDriver_writeAck) CF (memoryDriver_readLineReq, memoryDriver_readLineRsp, memoryDriver_writeLine, memoryDriver_writeAck);

    schedule (memoryDriver_readLineReq, memoryDriver_readLineRsp, memoryDriver_writeLine, memoryDriver_writeAck) CF
             (channelDriver_deq, channelDriver_write, channelDriver_notEmpty, channelDriver_notFull, channelDriver_first);

    schedule (sregDriver_sregReq, sregDriver_sregRsp) CF
             (channelDriver_deq, channelDriver_first, channelDriver_write, channelDriver_notEmpty, channelDriver_notFull,
              memoryDriver_readLineReq, memoryDriver_readLineRsp, memoryDriver_writeLine, memoryDriver_writeAck,
              sregDriver_sregReq, sregDriver_sregRsp);

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
              channelDriver_deq, channelDriver_first, channelDriver_write,
              channelDriver_notFull, channelDriver_notEmpty,
              memoryDriver_readLineReq, memoryDriver_readLineRsp,
              memoryDriver_writeLine, memoryDriver_writeAck,
              sregDriver_sregReq, sregDriver_sregRsp);
endmodule



module [CONNECTED_MODULE] mkQADevice#(Clock vl_clk_LPdomain_32ui,
                                      Reset ffs_vl_LP32ui_lp2sy_SoftReset_n)
    // Interface:
    (QA_DEVICE_PLAT);

    QA_DEVICE_PLAT device <- mkQADeviceSynth(vl_clk_LPdomain_32ui,
                                             ffs_vl_LP32ui_lp2sy_SoftReset_n);
    return device;
endmodule


(* synthesize *)
module mkQADeviceSynth#(Clock vl_clk_LPdomain_32ui,
                        Reset ffs_vl_LP32ui_lp2sy_SoftReset_n)
    // Interface:
    (QA_DEVICE_PLAT);

    let qa_clock = vl_clk_LPdomain_32ui;
    let qa_reset = ffs_vl_LP32ui_lp2sy_SoftReset_n;

    // FIFOs for coming out of QA domain.

    let qaDevice <- mkQADeviceImport(vl_clk_LPdomain_32ui,
                                     ffs_vl_LP32ui_lp2sy_SoftReset_n);
    let qaChannelDriver = qaDevice.channelDriver;
    let qaMemoryDriver = qaDevice.memoryDriver;
    let qaSRegDriver = qaDevice.sregDriver;


    //
    // Host/FPGA Channels
    //

    SyncFIFOIfc#(UMF_CHUNK) syncChannelReadQ <- mkSyncFIFOToCC(16, qa_clock, qa_reset);
    SyncFIFOIfc#(UMF_CHUNK) syncChannelWriteQ <- mkSyncFIFOFromCC(16, qa_clock);

    rule pullDataIn;
        syncChannelReadQ.enq(qaChannelDriver.first);
        qaChannelDriver.deq;
    endrule

    rule pushDataOut;
        qaChannelDriver.write(syncChannelWriteQ.first);
        syncChannelWriteQ.deq;
    endrule


    //
    // Memory
    //

    SyncFIFOIfc#(QA_CCI_ADDR) syncMemoryReadReqQ <-
        mkSyncFIFOFromCC(16, qa_clock);
    SyncFIFOIfc#(QA_CCI_DATA) syncMemoryReadRspQ <-
        mkSyncFIFOToCC(valueOf(QA_MAX_MEM_READS), qa_clock, qa_reset);
    SyncFIFOIfc#(Tuple2#(QA_CCI_ADDR, QA_CCI_DATA)) syncMemoryWriteQ <-
        mkSyncFIFOFromCC(16, qa_clock);

    // A stream of counts of completed writes.
    SyncFIFOIfc#(Bit#(QA_DEVICE_WRITE_ACK_BITS)) syncMemoryWriteAckQ <-
        mkSyncFIFOToCC(valueOf(QA_MAX_MEM_READS), qa_clock, qa_reset);

    // Count operations in flight to prevent overflows
    COUNTER#(TLog#(TAdd#(QA_MAX_MEM_READS, 1))) activeMemReads <- mkLCounter(0);
    COUNTER#(TLog#(TAdd#(QA_MAX_MEM_WRITES, 1))) activeMemWrites <- mkLCounter(0);

    rule fwdMemoryReadReq;
        qaMemoryDriver.readLineReq(syncMemoryReadReqQ.first);
        syncMemoryReadReqQ.deq;
    endrule

    (* fire_when_enabled *)
    rule fwdMemoryReadRsp;
        let d <- qaMemoryDriver.readLineRsp();
        syncMemoryReadRspQ.enq(d);
    endrule

    rule fwdMemoryWriteReq;
        match {.addr, .data} = syncMemoryWriteQ.first;
        syncMemoryWriteQ.deq;

        qaMemoryDriver.writeLine(addr, data);
    endrule


    // Counter in QA driver clock domain of completed writes.
    COUNTER#(TLog#(TAdd#(QA_MAX_MEM_WRITES, 1))) writeAcks <-
        mkLCounter(0, clocked_by qa_clock, reset_by qa_reset);

    (* fire_when_enabled, no_implicit_conditions *)
    rule noteWriteAck;
        let cnt <- qaMemoryDriver.writeAck();
        writeAcks.upBy(zeroExtend(cnt));
    endrule

    // Forward completed count to the platform.  Since there is a clock crossing
    // send whatever count is available each opportunity.
    rule fwdMemoryWritesInFlight (! writeAcks.isZero);
        // Local count of pending acks.
        let cur_cnt = writeAcks.value();

        // Smaller container in which to forward acks.
        Bit#(QA_DEVICE_WRITE_ACK_BITS) cnt_enq = maxBound;
        if (cur_cnt < zeroExtend(cnt_enq))
        begin
            cnt_enq = truncate(cur_cnt);
        end

        // Report cnt_enq acks through the queue this cycle
        syncMemoryWriteAckQ.enq(cnt_enq);
        writeAcks.downBy(zeroExtend(cnt_enq));
    endrule


    //
    // Status registers
    //

    SyncFIFOIfc#(QA_SREG_ADDR) syncSregReqQ <- mkSyncFIFOToCC(1, qa_clock, qa_reset);
    SyncFIFOIfc#(QA_SREG) syncSregRspQ <- mkSyncFIFOFromCC(1, qa_clock);

    (* fire_when_enabled *)
    rule sregReqIn;
        let r <- qaSRegDriver.sregReq();
        syncSregReqQ.enq(r);
    endrule

    rule sregRspOut;
        qaSRegDriver.sregRsp(syncSregRspQ.first);
        syncSregRspQ.deq;
    endrule


    interface QA_CHANNEL_DRIVER channelDriver;
        method deq = syncChannelReadQ.deq;
        method first = syncChannelReadQ.first;
        method notEmpty = syncChannelReadQ.notEmpty;
        method write = syncChannelWriteQ.enq;
        method notFull = syncChannelWriteQ.notFull;
    endinterface

    interface QA_MEMORY_DRIVER memoryDriver;
        // Read line request tracks the number of outstanding read requests
        // since there is no flow control in the Verilog driver.  The incoming
        // syncMemoryReadRspQ must be large enough to hold all outstanding
        // responses.
        method Action readLineReq(QA_CCI_ADDR addr) if (activeMemReads.value() < fromInteger(valueOf(QA_MAX_MEM_READS)));
            syncMemoryReadReqQ.enq(addr);
            activeMemReads.up();
        endmethod

        method ActionValue#(QA_CCI_DATA) readLineRsp();
            let d = syncMemoryReadRspQ.first();
            syncMemoryReadRspQ.deq();
            activeMemReads.down();

            return d;
        endmethod

        method Action writeLine(QA_CCI_ADDR addr, QA_CCI_DATA data) if (activeMemWrites.value() < fromInteger(valueOf(QA_MAX_MEM_WRITES)));
            syncMemoryWriteQ.enq(tuple2(addr, data));
            activeMemWrites.up();
        endmethod

        // Ack one or more writes.  More than one is handled per cycle because
        // the QA driver may return more than one a cycle.  In addition, the
        // user clock is often slower than the driver clock.
        method ActionValue#(Bit#(QA_DEVICE_WRITE_ACK_BITS)) writeAck();
            let n = syncMemoryWriteAckQ.first();
            syncMemoryWriteAckQ.deq();
            activeMemWrites.downBy(zeroExtend(n));

            return n;
        endmethod
    endinterface

    interface QA_SREG_DRIVER sregDriver; 
        method ActionValue#(QA_SREG_ADDR) sregReq();
            syncSregReqQ.deq();
            return syncSregReqQ.first();
        endmethod

        method sregRsp = syncSregRspQ.enq;
    endinterface

    interface QA_WIRES wires = qaDevice.wires;
endmodule
