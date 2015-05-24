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

import FIFO::*;
import Vector::*;
import Clocks::*;
import DefaultValue::*;


//
// Standard physical platform for Intel QuickAssist FPGAs.
//

`include "awb/provides/qa_device.bsh"
`include "awb/provides/clocks_device.bsh"
`include "awb/provides/ddr_sdram_device.bsh"
`include "awb/provides/ddr_sdram_definitions.bsh"

`include "awb/provides/physical_platform_utils.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"


// PHYSICAL_DRIVERS

// This represents the collection of all platform capabilities which the
// rest of the FPGA uses to interact with the outside world.
// We use other modules to actually do the work.

interface PHYSICAL_DRIVERS;
    interface CLOCKS_DRIVER   clocksDriver;
    interface QA_DRIVER       qaDriver;
    interface DDR_DRIVER      ddrDriver;
endinterface

// TOP_LEVEL_WIRES

// The TOP_LEVEL_WIRES is the datatype which gets passed to the top level
// and output as input/output wires. These wires are then connected to
// physical pins on the FPGA as specified in the accompanying UCF file.
// These wires are defined in the individual devices.

interface TOP_LEVEL_WIRES;
    (* prefix = "" *)
    interface CLOCKS_WIRES    qaClockWires;

    // wires from devices
    (* prefix = "" *)
    interface QA_WIRES        qaWires;
    interface DDR_WIRES       ddrWires;
endinterface

// PHYSICAL_PLATFORM

// The platform is the aggregation of wires and drivers.

interface PHYSICAL_PLATFORM;
    interface PHYSICAL_DRIVERS physicalDrivers;
    interface TOP_LEVEL_WIRES  topLevelWires;
endinterface

// mkPhysicalPlatform

// This is a convenient way for the outside world to instantiate all the devices
// and an aggregation of all the wires.

module [CONNECTED_MODULE] mkPhysicalPlatform
    //interface: 
    (PHYSICAL_PLATFORM);
    
    //
    // The Platform is instantiated inside a NULL clock domain. Our first
    // course of action should be to instantiate the Clocks Physical Device
    // and obtain interfaces to clock and reset the other devices with.
    //
    // The clock is derived from the QuickAssist vl_clk_LPDomain_32ui.
    // Reset is derived from ffs_vl_LP32ui_lp2sy_SoftReset_n.
    //
    CLOCKS_DEVICE clocks <- mkClocksDevice();
    
    Clock clk = clocks.driver.clock;
    Reset rst = clocks.driver.reset;

    let ddrConfig = defaultValue;
    ddrConfig.internalClock = clocks.driver.rawClock;
    ddrConfig.internalReset = clocks.driver.rawReset;
    ddrConfig.modelResetNeedsFanout = False;
    
    let ddrRst <- mkResetFanout(clocks.driver.baseReset, clocked_by clk);
    DDR_DEVICE sdram <- mkDDRDevice(ddrConfig,
                                    clocked_by clk,
                                    reset_by ddrRst);

    let qa_driver_clock = clocks.driver.rawClock;
    let qa_driver_reset = clocks.driver.rawReset;

    // Next, create the physical device that can trigger a soft reset. Pass along the
    // interface to the trigger module that the clocks device has given us.
    let qaRst <- mkResetFanout(clocks.driver.baseReset, clocked_by clk);
    QA_DEVICE qa <- mkQADevice(qa_driver_clock, qa_driver_reset,
                               clocks.softResetTrigger,
                               clocked_by clk,
                               reset_by qaRst);

    //
    // Pass reset from QA to the model.  The host holds reset long enough that
    // a crossing wire to the model clock domain is sufficient.
    //
    Reg#(Bool) qaInReset <- mkReg(True,
                                  clocked_by qa_driver_clock,
                                  reset_by qa_driver_reset);

    ReadOnly#(Bool) assertModelReset <-
        mkNullCrossingWire(clocks.driver.clock,
                           qaInReset,
                           clocked_by qa_driver_clock,
                           reset_by qa_driver_reset);
    
    (* fire_when_enabled, no_implicit_conditions *)
    rule exitResetQa (qaInReset);
        qaInReset <= False;
    endrule

    (* fire_when_enabled *)
    rule triggerModelReset (assertModelReset);
        clocks.softResetTrigger.reset();
    endrule

    //
    // Aggregate the drivers
    //
    interface PHYSICAL_DRIVERS physicalDrivers;
        interface clocksDriver = clocks.driver;
        interface qaDriver     = qa.driver;
        interface ddrDriver    = sdram.driver;
    endinterface
    
    //
    // Aggregate the wires
    //
    interface TOP_LEVEL_WIRES topLevelWires;
        interface qaClockWires = clocks.wires;
        interface qaWires      = qa.wires;
        interface ddrWires     = sdram.wires;
    endinterface
               
endmodule
