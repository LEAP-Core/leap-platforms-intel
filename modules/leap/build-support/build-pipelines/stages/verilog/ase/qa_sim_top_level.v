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



//
// This is the top level of the Intel QuickAssist simulation for LEAP.
// Bluespec expects the top level simulation build to have only CLK and RST_N.
// This module instantiates the simulation environment, which instantiates
// the user code through the usual QuickAssist cci_stf_afu() module.
//

import "DPI-C" function string getenv(input string env_name);

module qa_sim_top_level(CLK,
                        RST_N);
    input CLK;
    input RST_N;

    cci_emulator emulator();

    initial
    begin
        $dumpfile("driver_dump.vcd");
        if ({getenv("VCD_ENABLE_DUMP")} != "")
        begin
            $display("Enabling dump to driver_dump.vcd");
            $dumpvars(0, emulator);
            $dumpon;
        end
        else
        begin
            $display("VCD disabled. To enable: \"setenv VCD_ENABLE_DUMP 1\".");
            $system("rm -f driver_dump.vcd");
        end
    end
endmodule // qa_sim_top_level
