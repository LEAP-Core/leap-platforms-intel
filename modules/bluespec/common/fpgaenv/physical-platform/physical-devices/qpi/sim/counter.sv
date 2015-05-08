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
 * Module Info: Generic counter
 * Language   : System{Verilog}
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 */


module counter
  #(
    parameter int COUNT_WIDTH = 32
    )
   (
    input logic 		   clk,
    input logic 		   rst,
    input logic 		   cnt_en,
    input logic [COUNT_WIDTH-1:0]  load_cnt,
    input logic [COUNT_WIDTH-1:0]  max_cnt, 
    output logic [COUNT_WIDTH-1:0] count_out,
    output logic 		   terminal_cnt
    );

   logic [COUNT_WIDTH-1:0] 	   cnt_reg;
 	   
   // Count out
   assign count_out = cnt_reg;

   // Terminal count
   assign terminal_cnt = (cnt_reg == max_cnt) ? 1'b1 : 1'b0;
   
   // Counter process
   always @(posedge clk) begin
      if (rst == 1'b1) 
	cnt_reg <= load_cnt;
      else if ( (rst == 1'b0) && (cnt_en == 1'b1) &&  (cnt_reg < max_cnt) )
	cnt_reg <= cnt_reg + 1;
      else
	cnt_reg <= cnt_reg;      
   end

endmodule // counter

