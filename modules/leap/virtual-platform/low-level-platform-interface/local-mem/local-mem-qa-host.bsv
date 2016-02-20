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
// Local memory using Intel QuickAssist host memory.
//

`define LOCAL_MEM_READ_LATENCY    0
`define LOCAL_MEM_WRITE_LATENCY   0

import FIFO::*;
import FIFOF::*;
import Vector::*;
import List::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/common_services.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/qa_device.bsh"

`include "awb/dict/PARAMS_LOCAL_MEM.bsh"
//
// Configure local memory words as the entire QA CCI cache line.  Partial writes
// are slow, so we want to discourage them.
//
`define LOCAL_MEM_ADDR_BITS       `CCI_ADDR_WIDTH

typedef `LOCAL_MEM_ADDR_BITS LOCAL_MEM_ADDR_SZ;
`include "awb/provides/local_mem_interface.bsh"

typedef TMul#(LOCAL_MEM_WORD_SZ, LOCAL_MEM_WORDS_PER_LINE) LOCAL_MEM_BURST_DATA_SZ;


// Host-side memory allocator
`include "awb/rrr/client_stub_LOCAL_MEM_QA.bsh"

//
// platformHasLocalMem --
//     Allow clients to determine whether local memory actually exists.
//     Some models may wish to change their configuration for NULL local
//     memories.
//
function Bool platformHasLocalMem() = True;

typedef 1 LOCAL_MEM_BANKS;


module [CONNECTED_MODULE] mkLocalMem#(LOCAL_MEM_CONFIG conf)
    // interface:
    (LOCAL_MEM);

    if (`LOCAL_MEM_WORD_BITS != `CCI_DATA_WIDTH)
    begin
        error("LOCAL_MEM_WORD_BITS must match CCI_DATA_WIDTH");
    end

    //
    // The current local memory code supports only fixed sized requests.
    // CCI supports multi-line requests.  Check that the local memory
    // configuration maps to one of the supported multi-line options.
    //
    if ((`LOCAL_MEM_WORDS_PER_LINE != 1) &&
        (`LOCAL_MEM_WORDS_PER_LINE != 2) &&
        (`LOCAL_MEM_WORDS_PER_LINE != 4))
    begin
        error("LOCAL_MEM_WORDS_PER_LINE must match CCI multi-line options");
    end

    //
    // Host-side memory allocator
    //
    let allocator <- mkClientStub_LOCAL_MEM_QA();

    //
    // Connections to the host memory driver.
    //
    String platformName <- getSynthesisBoundaryPlatform();
    String hostMemoryName = "hostMemory_" + platformName + "_";

    CONNECTION_SEND#(QA_MEM_REQ) memReq <-
        mkConnectionSend(hostMemoryName + "req");

    CONNECTION_RECV#(QA_CCI_DATA) memReadLineRsp <-
        mkConnectionRecv(hostMemoryName + "readLineRsp");

    CONNECTION_RECV#(Bit#(QA_DEVICE_WRITE_ACK_BITS)) memWriteAck <-
        mkConnectionRecv(hostMemoryName + "writeAck");

    //
    // Dynamic parameters
    //
    PARAMETER_NODE paramNode <- mkDynamicParameterNode();
    Param#(1) enforceOrder <-
        mkDynamicParameter(`PARAMS_LOCAL_MEM_LOCAL_MEM_ENFORCE_ORDER,
                           paramNode);
    Bool checkLoadStoreOrder = (enforceOrder != 0);


    //
    // Track multi-beat reads and writes.
    //
    Reg#(Bit#(TLog#(LOCAL_MEM_WORDS_PER_LINE))) nWriteBeatsRem <- mkReg(0);
    Reg#(Bit#(TLog#(LOCAL_MEM_WORDS_PER_LINE))) writeBeatIdx <- mkRegU();
    Reg#(LOCAL_MEM_ADDR) writeMultiAddr <- mkRegU();
    Reg#(Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD)) writeMultiBuf <- mkRegU();

    Reg#(Bit#(TLog#(LOCAL_MEM_WORDS_PER_LINE))) nReadBeats <- mkReg(0);
    Reg#(Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD)) readMultiBuf <- mkRegU();
    FIFO#(LOCAL_MEM_LINE) readLineQ <- mkLFIFO();


    //
    // Gate for requests.  memReq.notFull must be here since request methods
    // are sent through wires and merged in fwdMemReq!
    //
    function Bool notBusy();
        return memReq.notFull() && (nWriteBeatsRem == 0);
    endfunction

    rule trackWrites (True);
        let n = memWriteAck.receive();
        memWriteAck.deq();
    endrule


    //
    // Merge read and write requests into a single request so they stay aligned.
    //
    RWire#(LOCAL_MEM_ADDR) readReqW <- mkRWire();
    RWire#(Tuple2#(LOCAL_MEM_ADDR, LOCAL_MEM_LINE)) writeReqW <- mkRWire();

    (* fire_when_enabled *)
    rule fwdMemReq (True);
        let r_addr = validValue(readReqW.wget);
        match {.w_addr, .w_data} = validValue(writeReqW.wget);

        // CCI's number of lines in a multi-beat request is 0 based
        Integer cci_num_lines = valueOf(LOCAL_MEM_WORDS_PER_LINE) - 1;

        if ((nWriteBeatsRem != 0) && (valueOf(LOCAL_MEM_WORDS_PER_LINE) > 1))
        begin
            // Finish a multi-line write request
            let w_req = QA_MEM_WRITE_REQ {
                            addr: writeMultiAddr | zeroExtend(writeBeatIdx),
                            data: writeMultiBuf[0],
                            numLines: fromInteger(cci_num_lines),
                            sop: False,
                            cached: False,
                            checkLoadStoreOrder: checkLoadStoreOrder };

            memReq.send(QA_MEM_REQ { read: tagged Invalid,
                                     write: tagged Valid w_req });

            nWriteBeatsRem <= nWriteBeatsRem - 1;
            writeBeatIdx <= writeBeatIdx + 1;
            writeMultiBuf <= shiftInAtN(writeMultiBuf, ?);
        end
        else
        begin
            let r_req = QA_MEM_READ_REQ {
                            addr: r_addr,
                            numLines: fromInteger(cci_num_lines),
                            cached: False,
                            checkLoadStoreOrder: checkLoadStoreOrder };

            Vector#(LOCAL_MEM_WORDS_PER_LINE, LOCAL_MEM_WORD) w_vec;
            w_vec = unpack(w_data);

            let w_req = QA_MEM_WRITE_REQ {
                            addr: w_addr,
                            data: w_vec[0],
                            numLines: fromInteger(cci_num_lines),
                            sop: True,
                            cached: False,
                            checkLoadStoreOrder: checkLoadStoreOrder };

            memReq.send(QA_MEM_REQ {
                          read: isValid(readReqW.wget) ? tagged Valid r_req :
                                                         tagged Invalid,
                          write: isValid(writeReqW.wget) ? tagged Valid w_req :
                                                           tagged Invalid });

            // Save remainder of multi-beat request
            if (isValid(writeReqW.wget))
            begin
                nWriteBeatsRem <= fromInteger(cci_num_lines);
            end

            writeMultiAddr <= w_addr;
            writeMultiBuf <= shiftInAtN(w_vec, ?);
            writeBeatIdx <= 1;
        end
    endrule


    //
    // Collect all beats of a read into a line.
    //
    rule collectReadLine (True);
        let data = memReadLineRsp.receive();
        memReadLineRsp.deq();

        let v = shiftInAtN(readMultiBuf, data);
        readMultiBuf <= v;

        if ((nReadBeats == fromInteger(valueOf(LOCAL_MEM_WORDS_PER_LINE) - 1)) ||
            (valueOf(LOCAL_MEM_WORDS_PER_LINE) == 1))
        begin
            nReadBeats <= 0;
            readLineQ.enq(pack(v));
        end
        else
        begin
            nReadBeats <= nReadBeats + 1;
        end
    endrule


    method Action readWordReq(LOCAL_MEM_ADDR addr) if (notBusy());
        error("Word-sized read/write not supported");
    endmethod

    method ActionValue#(LOCAL_MEM_WORD) readWordRsp();
        error("Word-sized read/write not supported");
        return ?;
    endmethod


    method Action readLineReq(LOCAL_MEM_ADDR addr) if (notBusy());
        readReqW.wset(addr);
    endmethod

    method ActionValue#(LOCAL_MEM_LINE) readLineRsp();
        let data = readLineQ.first();
        readLineQ.deq();

        return data;
    endmethod


    method Action writeWord(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data) if (notBusy());
        error("Word-sized read/write not supported");
    endmethod

    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data) if (notBusy());
        writeReqW.wset(tuple2(addr, data));
    endmethod

    method Action writeWordMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data, LOCAL_MEM_WORD_MASK mask) if (notBusy());
        error("Word-sized read/write not supported");
    endmethod

    method Action writeLineMasked(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data, LOCAL_MEM_LINE_MASK mask) if (notBusy());
        $display("Masked write not supported");
    endmethod

    method Action allocRegionReq(LOCAL_MEM_ADDR addr);
        allocator.makeRequest_Alloc(zeroExtend(addr));
    endmethod

    method ActionValue#(Maybe#(LOCAL_MEM_ALLOC_RSP)) allocRegionRsp();
        let base_addr <- allocator.getResponse_Alloc();
        return tagged Valid LOCAL_MEM_ALLOC_RSP { baseAddr: truncate(base_addr),
                                                  needsInitZero: False };
    endmethod
endmodule
