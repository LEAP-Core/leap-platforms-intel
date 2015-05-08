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
 * Module Info: CCI Rules checker
 * Language   : System{Verilog} | C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 * Description: Checks the TX signals in AFU to see if 'X' or 'z' is validated
 *              ASE has not validated 'X', 'z' on RX channels, these will not be checked
 *              When error is discovered, it will be passed to a kill process
 *
 */

`include "ase_global.vh"

module cci_rule_checker
  #(
    parameter int TX_HDR_WIDTH = 61,
    parameter int RX_HDR_WIDTH = 18,
    parameter int DATA_WIDTH = 512,
    parameter int TIMESLOT_WIDTH = 32
    )
  (
   // Checker enable signal
   input logic 			     enable,
   // CCI-standard interface
   input logic 			     clk,
   input logic 			     resetb ,
   input logic 			     lp_initdone ,
   input logic [TX_HDR_WIDTH-1:0]    tx_c0_header,
   input logic 			     tx_c0_rdvalid,
   input logic [TX_HDR_WIDTH-1:0]    tx_c1_header,
   input logic [DATA_WIDTH-1:0]      tx_c1_data,
   input logic 			     tx_c1_wrvalid,
   input logic 			     tx_c1_intrvalid,
   input logic [RX_HDR_WIDTH-1:0]    rx_c0_header,
   input logic [DATA_WIDTH-1:0]      rx_c0_data,
   input logic 			     rx_c0_cfgvalid,
   input logic 			     rx_c0_rdvalid,
   input logic 			     rx_c0_wrvalid,
   input logic [RX_HDR_WIDTH-1:0]    rx_c1_header,
   input logic 			     rx_c1_wrvalid,
   // Errors
   output logic 		     tx_ch0_error,
   output logic 		     tx_ch1_error,
   output logic 		     rx_ch0_error,
   output logic 		     rx_ch1_error,
   output logic [TIMESLOT_WIDTH-1:0] tx_ch0_time,
   output logic [TIMESLOT_WIDTH-1:0] tx_ch1_time,
   output logic [TIMESLOT_WIDTH-1:0] rx_ch0_time,
   output logic [TIMESLOT_WIDTH-1:0] rx_ch1_time
   );

   /*
    * Internal enable
    */
   logic 			       internal_en;
   always @(*) begin
      if ( (resetb == 1'b1) && (lp_initdone == 1'b1) && (enable == 1'b1) )
	internal_en <= 1'b1;
      else
	internal_en <= 1'b0;
   end

   /*
    * TX checker flags
    */
   logic tx0_flag;
   logic tx1_flag;
   logic rx0_flag;
   logic rx1_flag;
      
   assign tx0_flag = ^tx_c0_header;
   assign tx1_flag = ^tx_c1_header || ^tx_c1_data;
   assign rx0_flag = ^rx_c0_header || ^rx_c0_data;
   assign rx1_flag = ^rx_c1_header;
   
   /*
    * Checking process
    */
   always @(posedge clk) begin
      if (internal_en == 1'b0) begin
	 tx_ch0_error <= 1'b0;
	 tx_ch1_error <= 1'b0;
	 rx_ch0_error <= 1'b0;
	 rx_ch1_error <= 1'b0;
      end
      else begin
	 // TX0
	 if (tx_c0_rdvalid == 1'b1) begin
	    case (tx0_flag)
	      `VLOG_HIIMP: // 1'bz:
		begin
		   tx_ch0_error <= 1'b1;
		   tx_ch0_time <= $time;
		end
	      `VLOG_UNDEF: // 1'bx:
		begin
		   tx_ch0_error <= 1'b1;
		   tx_ch0_time <= $time;
		end
	    endcase // case (tx0_flag)
	 end
	 // TX1
	 if (tx_c1_wrvalid == 1'b1) begin
	    case (tx1_flag)
	      `VLOG_HIIMP: // 1'bz:
		begin
		   tx_ch1_error <= 1'b1;
		   tx_ch1_time <= $time;
		end
	      `VLOG_UNDEF: // 1'bx:
		begin
		   tx_ch1_error <= 1'b1;
		   tx_ch1_time <= $time;
		end
	    endcase // case (tx1_flag)
	 end
	 // RX0
	 if ((rx_c0_rdvalid == 1'b1) || (rx_c0_wrvalid == 1'b1) || (rx_c0_cfgvalid == 1'b1)) begin
	    case (rx0_flag)
	      `VLOG_HIIMP: // 1'bz:
		begin
		   rx_ch0_error <= 1'b1;
		   rx_ch0_time <= $time;
		end
	      `VLOG_UNDEF: // 1'bx:
		begin
		   rx_ch0_error <= 1'b1;
		   rx_ch0_time <= $time;
		end
	    endcase // case (tx0_flag)
	 end
	 // RX1
	 if (rx_c1_wrvalid == 1'b1) begin
	    case (rx1_flag)
	      `VLOG_HIIMP: // 1'bz:
		begin
		   rx_ch1_error <= 1'b1;
		   rx_ch1_time <= $time;
		end
	      `VLOG_UNDEF: // 1'bx:
		begin
		   rx_ch1_error <= 1'b1;
		   rx_ch1_time <= $time;
		end
	    endcase // case (tx1_flag)
	 end 	 
      end
   end


endmodule
