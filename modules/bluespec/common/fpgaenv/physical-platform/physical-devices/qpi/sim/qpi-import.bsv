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

// This code wraps the QPI CCI (coherent cache interface) in bluespec.

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


interface QPI_DRIVER;

    method Action                           deq();
    method Bit#(SizeOf#(UMF_CHUNK))         first();
    method Action                           write(Bit#(SizeOf#(UMF_CHUNK)) chunk);
    method Bool                             write_ready();

    interface Clock clock;
    interface Reset reset;

endinterface

interface QPI_WIRES;

endinterface

interface QPI_DEVICE;
    interface QPI_DRIVER driver; 
    interface QPI_WIRES  wires;
endinterface

// tx_header ~some request to the cache
// rx_header ~some response from the cache
interface QPI_DEVICE_UG#(numeric type tx_header, numeric type rx_header, numeric type cache_width);

    method Action                           deq();
    method Bit#(SizeOf#(UMF_CHUNK))         first();
    method Action                           write(Bit#(SizeOf#(UMF_CHUNK)) chunk);
    method Bool                             write_ready();

    interface Clock qpi_clk;
    interface Reset qpi_rst_n;
endinterface

Integer umfChunkSize = valueOf(SizeOf#(UMF_CHUNK));

import "BVI" qpi_wrapper = 
module mkQPIDeviceImport  (QPI_DRIVER);

    parameter TXHDR_WIDTH = `CCI_TXHDR_WIDTH;
    parameter RXHDR_WIDTH = `CCI_RXHDR_WIDTH;
    parameter CACHE_WIDTH = `CCI_CACHE_WIDTH;
    parameter UMF_WIDTH   = umfChunkSize;

    output_clock clock(clk);
    output_reset reset(resetb) clocked_by (clock);

    default_clock no_clock;
    default_reset no_reset;

    method deq() ready(rx_rdy) enable(rx_enable) clocked_by(clock) reset_by(reset);
    method rx_data first() ready(rx_rdy) clocked_by(clock) reset_by(reset);
    method write(tx_data) ready(tx_rdy) enable(tx_enable) clocked_by(clock) reset_by(reset);
    method tx_not_full write_ready() clocked_by(clock) reset_by(reset);

    schedule (deq) C (deq);
    schedule (deq) CF (first, write, write_ready);
    schedule (first) CF (deq, first, write, write_ready);
    schedule (write) C (write);    
    schedule (write) CF (deq, first, write_ready);
    schedule (write_ready) CF (deq, first, write, write_ready);

endmodule

module [CONNECTED_MODULE] mkQPIDevice#(SOFT_RESET_TRIGGER softResetTrigger) (QPI_DEVICE);

    // FIFOs for coming out of QPI domain.

    let qpiDevice <- mkQPIDeviceImport; 

    SyncFIFOIfc#(UMF_CHUNK) syncReadQ <- mkSyncFIFOToCC(16, qpiDevice.clock, qpiDevice.reset);
    SyncFIFOIfc#(UMF_CHUNK) syncWriteQ <- mkSyncFIFOFromCC(16, qpiDevice.clock);

    rule pullDataIn;
        syncReadQ.enq(qpiDevice.first);
        qpiDevice.deq;
    endrule

    rule pushDataOut;
        qpiDevice.write(syncWriteQ.first);
        syncWriteQ.deq;
    endrule

    interface QPI_DRIVER driver;
        method deq = syncReadQ.deq;
        method first = syncReadQ.first;
        method write = syncWriteQ.enq;
        method write_ready = syncWriteQ.notFull;

        interface clock = qpiDevice.clock;
        interface reset = qpiDevice.reset;
    endinterface

    interface QPI_WIRES wires;
            
    endinterface

endmodule
