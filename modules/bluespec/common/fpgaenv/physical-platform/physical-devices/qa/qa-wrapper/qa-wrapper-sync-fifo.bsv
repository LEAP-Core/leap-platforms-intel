//
// Copyright (c) 2016, Intel Corporation
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

import Clocks::*;
import FIFO::*;
import FIFOF::*;

`include "awb/provides/qa_platform_libs.bsh"

`ifndef CCI_S_IFC_Z
  `define USE_BLUESPEC_SYNCFIFO 1
`endif


module mkQASyncFIFOFromCC#(Integer depth, Clock dClk)
    // Interface:
    (SyncFIFOIfc#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    let sClk <- exposeCurrentClock();
    let sRst <- exposeCurrentReset();

`ifdef USE_BLUESPEC_SYNCFIFO

    let s <- mkSyncFIFOFromCC(depth, dClk);
    return s;

`else

    let f <- mkQADCFIFO(depth, sClk, sRst, dClk);
    method Action enq(t_DATA sendData) = f.enq(sendData);
    method Action deq = f.deq;
    method t_DATA first = f.first;
    method Bool notFull = f.notFull;
    method Bool notEmpty = f.notEmpty;

`endif
endmodule


module mkQASyncFIFOToCC#(Integer depth, Clock sClk, Reset sRst)
    // Interface:
    (SyncFIFOIfc#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    let dClk <- exposeCurrentClock();

`ifdef USE_BLUESPEC_SYNCFIFO

    let s <- mkSyncFIFOToCC(depth, sClk, sRst);
    return s;

`else

    let f <- mkQADCFIFO(depth, sClk, sRst, dClk);
    method Action enq(t_DATA sendData) = f.enq(sendData);
    method Action deq = f.deq;
    method t_DATA first = f.first;
    method Bool notFull = f.notFull;
    method Bool notEmpty = f.notEmpty;

`endif
endmodule


interface QA_DCFIFO#(type t_DATA);
    method t_DATA first();
    method Action deq();
    method Bool notEmpty();
    method Action enq(t_DATA data);
    method Bool notFull();
endinterface

import "BVI" qa_wrapper_dcfifo = 
module mkQADCFIFO#(Integer depth, Clock sClk, Reset sRst, Clock dClk)
    // Interface:
    (QA_DCFIFO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    parameter DEPTH = depth;
    parameter WIDTH = valueOf(t_DATA_SZ);

    input_clock (sClk) = sClk;
    default_clock sClk;
    input_reset (sRst) = sRst;
    default_reset sRst;

    input_clock (dClk) = dClk;

    method first first() ready(notEmpty) clocked_by(dClk);
    method deq() ready(notEmpty) enable(deq) clocked_by(dClk);
    method notEmpty notEmpty() clocked_by(dClk);
    method enq(enq_data) ready(notFull) enable(enq_en);
    method notFull notFull();

    schedule (deq) C (deq);
    schedule (deq) CF (first, enq, notEmpty, notFull);
    schedule (first) CF (deq, first, enq, notEmpty, notFull);
    schedule (enq) C (enq);
    schedule (enq) CF (deq, first, notEmpty, notFull);
    schedule (notFull, notEmpty) CF (deq, first, enq, notEmpty, notFull);
endmodule
