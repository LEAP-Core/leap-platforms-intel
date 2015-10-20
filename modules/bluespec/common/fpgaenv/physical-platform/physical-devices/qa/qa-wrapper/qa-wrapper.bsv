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
import ConfigReg::*;

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
typedef 80 QA_MAX_MEM_READS;

// Maximum outstanding memory requests.  Allow many writes since the overhead
// here is low.  (Just a counter.)
typedef 256 QA_MAX_MEM_WRITES;

typedef Bit#(32) QA_SREG_ADDR;
typedef Bit#(64) QA_SREG;

typedef Bit#(`CCI_ADDR_WIDTH) QA_CCI_ADDR;
typedef Bit#(`CCI_DATA_WIDTH) QA_CCI_DATA;


//
// QA memory request type combines both read and write requests in a
// single connection so they stay ordered.
//

typedef struct
{
    QA_CCI_ADDR addr;

    // Cached in FPGA CCI?
    Bool cached;
    // Enforce load store order in the driver?
    Bool checkLoadStoreOrder;
}
QA_MEM_READ_REQ
    deriving (Eq, Bits);

typedef struct
{
    QA_CCI_ADDR addr;
    QA_CCI_DATA data;

    // Cached in FPGA CCI?
    Bool cached;
    // Enforce load store order in the driver?
    Bool checkLoadStoreOrder;
}
QA_MEM_WRITE_REQ
    deriving (Eq, Bits);

typedef struct
{
    Maybe#(QA_MEM_READ_REQ) read;
    Maybe#(QA_MEM_WRITE_REQ) write;
}
QA_MEM_REQ
    deriving (Eq, Bits);


//
// Channel interface exposed to the platform.
//
interface QA_CHANNEL_DRIVER;
    method Action                     deq();
    method Bit#(SizeOf#(UMF_CHUNK))   first();
    method Bool                       notEmpty();
    method Action                     write(Bit#(SizeOf#(UMF_CHUNK)) chunk);
    method Bool                       notFull();
endinterface

//
// Channel driver interface through the imported Verilog.
//
interface QA_CHANNEL_DRIVER_IMPORT;
    method Action                     deq();
    method QA_CCI_DATA                first();
    method Bool                       notEmpty();
    method Action                     write(QA_CCI_DATA data);
    method Bool                       notFull();
endinterface

//
// Memory driver interface exposed to the platform.
//
interface QA_MEMORY_DRIVER#(numeric type n_WRITE_ACK_BITS);
    method Action req(QA_MEM_REQ r);

    method ActionValue#(QA_CCI_DATA) readLineRsp();

    // True if any writes are still in flight
    method ActionValue#(Bit#(n_WRITE_ACK_BITS)) writeAck();
endinterface

//
// Memory driver interface through the imported Verilog.
//
interface QA_MEMORY_DRIVER_IMPORT#(numeric type n_WRITE_ACK_BITS);
    method Action readLineReq(QA_CCI_ADDR addr,
                              Bool cached,
                              Bool checkLoadStoreOrder);
    method ActionValue#(QA_CCI_DATA) readLineRsp();

    method Action writeLine(QA_CCI_ADDR addr,
                            QA_CCI_DATA data,
                            Bool cached,
                            Bool checkLoadStoreOrder);

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

interface QA_DEVICE#(type t_QA_CHANNEL_DRIVER, type t_QA_MEMORY_DRIVER);
    interface t_QA_CHANNEL_DRIVER channelDriver; 
    interface t_QA_MEMORY_DRIVER  memoryDriver;
    interface QA_SREG_DRIVER      sregDriver; 
    (* prefix = "" *)
    interface QA_WIRES            wires;
endinterface

// Import-BVI version of the interface with 2-bit memory write ACK.
typedef QA_DEVICE#(QA_CHANNEL_DRIVER_IMPORT,
                   QA_MEMORY_DRIVER_IMPORT#(2)) QA_DEVICE_IMPORT;

// Bluespec platform version of the interface with 4-bit memory write ACK in
// order to cope with latency-insensitivity and slower clocks.
typedef 4 QA_DEVICE_WRITE_ACK_BITS;
typedef QA_DEVICE#(QA_CHANNEL_DRIVER,
                   QA_MEMORY_DRIVER#(QA_DEVICE_WRITE_ACK_BITS)) QA_DEVICE_PLAT;


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

    input_clock (vl_clk_LPdomain_32ui) = vl_clk_LPdomain_32ui;
    default_clock vl_clk_LPdomain_32ui;

    input_reset (ffs_vl_LP32ui_lp2sy_SoftReset_n) = ffs_vl_LP32ui_lp2sy_SoftReset_n;
    default_reset ffs_vl_LP32ui_lp2sy_SoftReset_n;

    interface QA_CHANNEL_DRIVER_IMPORT channelDriver;
        method deq() ready(rx_fifo_rdy) enable(rx_fifo_enable);
        method rx_fifo_data first() ready(rx_fifo_rdy);
        method rx_fifo_rdy notEmpty();
        method write(tx_fifo_data) ready(tx_fifo_rdy) enable(tx_fifo_enable);
        method tx_fifo_rdy notFull();
    endinterface

    interface QA_MEMORY_DRIVER_IMPORT memoryDriver;
        method readLineReq(mem_read_req_addr,
                           mem_read_req_cached,
                           mem_read_req_check_order) ready(mem_read_req_rdy) enable(mem_read_req_enable);
        method mem_read_rsp_data readLineRsp() ready(mem_read_rsp_rdy) enable((*inhigh*) en0);

        method writeLine(mem_write_addr,
                         mem_write_data,
                         mem_write_req_cached,
                         mem_write_req_check_order) ready(mem_write_rdy) enable(mem_write_enable);
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
    (QA_DEVICE_PLAT)
    provisos (Bits#(UMF_CHUNK, n_UMF_CHUNK_SZ),
              Bits#(QA_CCI_DATA, n_QA_CCI_DATA_SZ),
              NumAlias#(n_CHUNKS_PER_LINE, TDiv#(n_QA_CCI_DATA_SZ, n_UMF_CHUNK_SZ)),
              Alias#(t_NUM_CHUNKS, Bit#(TLog#(n_CHUNKS_PER_LINE))),
              Alias#(t_CHUNK_VEC, Vector#(n_CHUNKS_PER_LINE, UMF_CHUNK)));

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

    //
    // Extract UMF_CHUNKS from the incoming cache line sized vector coming
    // from the driver.
    //
    Reg#(t_CHUNK_VEC) readChunkVec <- mkRegU(clocked_by qa_clock, reset_by qa_reset);
    // Number of chunks remaining in current line
    Reg#(t_NUM_CHUNKS) nReadVecChunksRem <- mkConfigReg(0, clocked_by qa_clock, reset_by qa_reset);
    // Number of chunks remaining in current UMF packet
    Reg#(UMF_MSG_LENGTH) nReadPacketChunksRem <- mkConfigReg(0, clocked_by qa_clock, reset_by qa_reset);

    //
    // Convert incoming lines from the channel to UMF_CHUNKs.
    //
    rule pullDataIn;
        t_CHUNK_VEC v;
        if (nReadVecChunksRem == 0)
        begin
            // Time for a new line from the channel
            v = unpack(qaChannelDriver.first);
            qaChannelDriver.deq();
            nReadVecChunksRem <= fromInteger(valueOf(n_CHUNKS_PER_LINE) - 1);
        end
        else
        begin
            // Chunks remain in the current line
            v = shiftInAtN(readChunkVec, ?);
            nReadVecChunksRem <= nReadVecChunksRem - 1;
        end

        readChunkVec <= v;

        if (nReadPacketChunksRem == 0)
        begin
            // Beginning of a UMF packet.  Find the length of the packet.
            UMF_MSG_LENGTH rem = truncate(v[0]);
            nReadPacketChunksRem <= rem;

            // Is this chunk a header or is it just filler in the line for
            // alignment?  It is a header if the packet length is not zero.
            if (rem != 0)
            begin
                syncChannelReadQ.enq(v[0]);
            end
        end
        else
        begin
            syncChannelReadQ.enq(v[0]);
            nReadPacketChunksRem <= nReadPacketChunksRem - 1;
        end
    endrule


    //
    // Merge UMF_CHUNKs into cache line sized vectors before writing them to
    // the host.  When the number of chunks isn't a multiple of the line size
    // it may be necessary to flush a line before it is complete in order to
    // transmit a message to the host.
    //
    Reg#(t_CHUNK_VEC) writeChunkVec <- mkRegU(clocked_by qa_clock, reset_by qa_reset);
    // Number of chunks valid in current line
    Reg#(t_NUM_CHUNKS) nWriteChunksActive <- mkConfigReg(0, clocked_by qa_clock, reset_by qa_reset);
    // Number of chunks remaining in current UMF packet
    Reg#(UMF_MSG_LENGTH) nWriteChunksRem <- mkConfigReg(0, clocked_by qa_clock, reset_by qa_reset);
    // Idle cycles since last chunk arrived
    Reg#(Bit#(4)) nWriteIdleCycles <- mkConfigReg(0, clocked_by qa_clock, reset_by qa_reset);

    PulseWire didWriteFlushW <- mkPulseWire(clocked_by qa_clock, reset_by qa_reset);

    rule pushDataOut (syncChannelWriteQ.notEmpty);
        // Shift the next entry in to the output buffer
        t_CHUNK_VEC v = shiftInAtN(writeChunkVec, syncChannelWriteQ.first);
        writeChunkVec <= v;
        syncChannelWriteQ.deq;

        if (nWriteChunksActive == (fromInteger(valueOf(n_CHUNKS_PER_LINE) - 1)))
        begin
            // Finished a line
            qaChannelDriver.write(pack(v));
            nWriteChunksActive <= 0;
        end
        else
        begin
            // Incomplete line
            nWriteChunksActive <= nWriteChunksActive + 1;
        end

        //
        // Track UMF packets.  Once a packet starts it will be stored densely
        // in the output stream.
        //
        if (nWriteChunksRem == 0)
        begin
            // Chunk is the start of a packet.  Get the count of chunks
            // left in the packet.
            nWriteChunksRem <= truncate(syncChannelWriteQ.first);
        end
        else
        begin
            nWriteChunksRem <= nWriteChunksRem - 1;
        end
    endrule

    // Count idle cycles when data is buffered so it can be flushed to the
    // host if necessary.
    (* no_implicit_conditions, fire_when_enabled *)
    rule countDataOutIdle (True);
        if (syncChannelWriteQ.notEmpty ||
           (nWriteChunksRem != 0) ||
           (nWriteChunksActive == 0) ||
           didWriteFlushW)
        begin
            nWriteIdleCycles <= 0;
        end
        else
        begin
            nWriteIdleCycles <= nWriteIdleCycles + 1;
        end
    endrule


    // Flush the output channel buffer to the host if no UMF packet is active
    // and too much time has passed.
    rule flushDataOut (! syncChannelWriteQ.notEmpty &&
                       (msb(nWriteIdleCycles) == 1));
        // Time to flush the buffer.  Rotate and flush when it is rotated
        // into the proper position.  Rotation may take multiple cycles.
        // If new data arrives before rotation then the flush sequence
        // terminates and real output resumes.  The host will handle an
        // arbitrary number of NULLs interted between UMF packets.
        t_CHUNK_VEC v = shiftInAtN(writeChunkVec, 0);
        writeChunkVec <= v;

        if (nWriteChunksActive == (fromInteger(valueOf(n_CHUNKS_PER_LINE) - 1)))
        begin
            // Finished a line
            qaChannelDriver.write(pack(v));
            nWriteChunksActive <= 0;
            didWriteFlushW.send();
        end
        else
        begin
            // Incomplete line
            nWriteChunksActive <= nWriteChunksActive + 1;
        end
    endrule


    //
    // Memory
    //

    SyncFIFOIfc#(QA_MEM_REQ) syncMemoryReqQ <-
        mkSyncFIFOFromCC(16, qa_clock);
    SyncFIFOIfc#(QA_CCI_DATA) syncMemoryReadRspQ <-
        mkSyncFIFOToCC(valueOf(QA_MAX_MEM_READS), qa_clock, qa_reset);

    // A stream of counts of completed writes.
    SyncFIFOIfc#(Bit#(QA_DEVICE_WRITE_ACK_BITS)) syncMemoryWriteAckQ <-
        mkSyncFIFOToCC(valueOf(QA_MAX_MEM_READS), qa_clock, qa_reset);

    // Count operations in flight to prevent overflows
    COUNTER#(TLog#(TAdd#(QA_MAX_MEM_READS, 1))) activeMemReads <- mkLCounter(0);
    COUNTER#(TLog#(TAdd#(QA_MAX_MEM_WRITES, 1))) activeMemWrites <- mkLCounter(0);

    function Bool canStartReq();
        return (activeMemReads.value() < fromInteger(valueOf(QA_MAX_MEM_READS))) &&
               (activeMemWrites.value() < fromInteger(valueOf(QA_MAX_MEM_WRITES)));
    endfunction

    rule fwdMemoryReq;
        let req = syncMemoryReqQ.first();
        syncMemoryReqQ.deq();

        if (req.read matches tagged Valid .read)
        begin
            qaMemoryDriver.readLineReq(read.addr,
                                       read.cached, read.checkLoadStoreOrder);
        end

        if (req.write matches tagged Valid .write)
        begin
            qaMemoryDriver.writeLine(write.addr, write.data,
                                     write.cached, write.checkLoadStoreOrder);
        end
    endrule

    (* fire_when_enabled *)
    rule fwdMemoryReadRsp;
        let d <- qaMemoryDriver.readLineRsp();
        syncMemoryReadRspQ.enq(d);
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
        method Action req(QA_MEM_REQ r) if (canStartReq);
            syncMemoryReqQ.enq(r);

            if (isValid(r.read))
            begin
                activeMemReads.up();
            end

            if (isValid(r.write))
            begin
                activeMemWrites.up();
            end
        endmethod

        method ActionValue#(QA_CCI_DATA) readLineRsp();
            let d = syncMemoryReadRspQ.first();
            syncMemoryReadRspQ.deq();
            activeMemReads.down();

            return d;
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
