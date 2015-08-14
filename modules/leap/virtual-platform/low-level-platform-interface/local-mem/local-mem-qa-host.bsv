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

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/qa_device.bsh"

//
// Configure local memory words as the entire QA CCI cache line.  Partial writes
// are slow, so we want to discourage them.
//
`define LOCAL_MEM_ADDR_BITS       `CCI_ADDR_WIDTH
`define LOCAL_MEM_WORD_BITS       `CCI_DATA_WIDTH
`define LOCAL_MEM_WORDS_PER_LINE  1

typedef `LOCAL_MEM_ADDR_BITS LOCAL_MEM_ADDR_SZ;
`include "awb/provides/local_mem_interface.bsh"

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
    // Gate for requests.  memReq.notFull must be here since request methods
    // are sent through wires and merged in fwdMemReq!
    //
    function Bool notBusy();
        return memReq.notFull();
    endfunction

    rule trackWrites (True);
        let n = memWriteAck.receive();
        memWriteAck.deq();
    endrule


    //
    // Merge read and write requests into a single request so they stay aligned.
    //
    RWire#(QA_MEM_READ_REQ) readReqW <- mkRWire();
    RWire#(QA_MEM_WRITE_REQ) writeReqW <- mkRWire();

    (* fire_when_enabled *)
    rule fwdMemReq (isValid(readReqW.wget) || isValid(writeReqW.wget));
        memReq.send(QA_MEM_REQ { read: readReqW.wget, write: writeReqW.wget });
    endrule


    method Action readWordReq(LOCAL_MEM_ADDR addr) if (notBusy());
        error("Word-sized read/write not supported");
    endmethod

    method ActionValue#(LOCAL_MEM_WORD) readWordRsp();
        error("Word-sized read/write not supported");
        return ?;
    endmethod


    method Action readLineReq(LOCAL_MEM_ADDR addr) if (notBusy());
        match {.l_addr, .w_idx} = localMemSeparateAddr(addr);

        readReqW.wset(QA_MEM_READ_REQ { addr: l_addr });
    endmethod

    method ActionValue#(LOCAL_MEM_LINE) readLineRsp();
        let data = memReadLineRsp.receive();
        memReadLineRsp.deq();

        return data;
    endmethod


    method Action writeWord(LOCAL_MEM_ADDR addr, LOCAL_MEM_WORD data) if (notBusy());
        error("Word-sized read/write not supported");
    endmethod

    method Action writeLine(LOCAL_MEM_ADDR addr, LOCAL_MEM_LINE data) if (notBusy());
        match {.l_addr, .w_idx} = localMemSeparateAddr(addr);

        writeReqW.wset(QA_MEM_WRITE_REQ { addr: l_addr, data: data });
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
