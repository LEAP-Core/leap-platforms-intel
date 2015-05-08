/* ****************************************************************************
 * Copyright (c) 2011-2015, Intel Corporation
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * * Neither the name of Intel Corporation nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * **************************************************************************
 * 
 * Module Info: Single Port RAM implementation
 * Language   : System{Verilog} | C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 */
 
module sdp_ram
  #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH_BASE2 = 4
    )
   (
    input logic 		  clk,
    input logic 		  we,
    input logic [DEPTH_BASE2-1:0] waddr,
    input logic [DATA_WIDTH-1:0]  din,
    input logic [DEPTH_BASE2-1:0] raddr,
    output logic [DATA_WIDTH-1:0] dout
    ); 

   // Memory
   reg [DATA_WIDTH-1:0] 	  ram [(2**DEPTH_BASE2)-1:0];
   
   reg [DEPTH_BASE2-1:0] 	  raddr_q;
   reg [DATA_WIDTH-1:0] 	  ram_dout;
   
   always @(posedge clk) begin
      if (we)
	ram[waddr]<=din; // synchronous write the RAM
   end
   
   always @(posedge clk) begin
      raddr_q <= raddr;
      dout    <= ram_dout;
   end
   
   always @(*) begin
      ram_dout = ram[raddr_q];
   end
   
endmodule


