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


`include "awb/provides/soft_connections.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"

`include "awb/provides/physical_platform.bsh"

// ============== Physical Platform Debugger ==============

// the debugger accepts a set of physical drivers as
// constructor input (along with some status bits), and
// returns exactly the same set of physical drivers as its
// interface

// module
module [CONNECTED_MODULE] mkPhysicalPlatformDebugger#(PHYSICAL_DRIVERS drivers)
    // interface
    (PHYSICAL_DRIVERS);
    
    let qa = drivers.qaSRegDriver;

`ifndef QA_ENABLE_PLATFORM_DEBUGGER_Z

    //
    // The debugger implements a history ring buffer.  Buffer entries are mapped
    // to register numbers and accessed through the QA driver's SREG interface.
    // The SREG interface is part of the driver, not the standard QA signals.
    // The ReadSREG method in the driver can access the values.
    //
    // The origin of the history buffer moves with each new value sent to
    // the soft connection.  ReadSREG(1) reads the newest entry, ReadSREG(2)
    // the 2nd most recent, etc.
    //

    // Client connection
    CONNECTION_RECV#(QA_SREG) sregUpdateQ <- mkConnectionRecvOptional("qa_sreg_dbg_ring");

    // 512 entry ring buffer
    MEMORY_IFC#(Bit#(9), QA_SREG) sregs <- mkBRAM();
    Reg#(Bit#(9)) nextWriteIdx <- mkReg(0);

    // Write registers, using memory as a ring buffer
    rule updateReg (True);
        let v = sregUpdateQ.receive();
        sregUpdateQ.deq();

        sregs.write(nextWriteIdx, v);
        nextWriteIdx <= nextWriteIdx + 1;
    endrule

    // Read registers
    rule regReadReq (True);
        let r <- qa.sregReq();

        // The origin of the register index is the most recently written entry.
        sregs.readReq(nextWriteIdx - truncate(r));
    endrule

    rule regReadRsp (True);
        let v <- sregs.readRsp();
        qa.sregRsp(v);
    endrule

`endif

    return drivers;
endmodule
