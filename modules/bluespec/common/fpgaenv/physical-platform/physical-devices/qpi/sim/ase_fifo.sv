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
 * Module Info:
 * Language   : System{Verilog} 
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 * FIFO implementation for use in ASE only
 * Generics: 
 * - DEPTH_BASE2    : Radix of element array, used for counting elements
 * - ALMFULL_THRESH : AlmostFull threshold
 * 
 */
 
module ase_fifo
  #(
    parameter int DATA_WIDTH = 64,
    parameter int DEPTH_BASE2 = 3,
    parameter int ALMFULL_THRESH = 5
    )
   (
    input logic 		  clk,
    input logic 		  rst,
    input logic 		  wr_en,
    input logic [DATA_WIDTH-1:0]  data_in,
    input logic 		  rd_en,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic 		  data_out_v,
    output logic 		  alm_full,
    output logic 		  full,
    output logic 		  empty,
    output logic [DEPTH_BASE2:0]  count,
    output logic 		  overflow,
    output logic 		  underflow
    );

   logic 			  valid;
   logic 			  prog_full;   
   logic 			  mywr_en;
   logic 			  empty_current;
   logic 			  empty_next;
   logic 			  full_current;
   logic 			  full_next;
   logic [DEPTH_BASE2-1:0] 	  rd_addr;
   logic [DEPTH_BASE2-1:0] 	  wr_addr;
   logic [DEPTH_BASE2:0] 	  counter;
   
   // discard incoming data when FIFO is full
   assign mywr_en = wr_en & (~full_current);
   assign count   = counter [DEPTH_BASE2-1:0];

   // writing pointer doesn't change when overflow
   always @(posedge clk) begin
      if (rst == 1'b1)
	wr_addr <= 0;
      else begin
	 if (mywr_en) 
	   wr_addr <= wr_addr + 1'b1;
      end
   end
   
   // overflow being asserted for one cycle means one incoming data was discarded
   always @(posedge clk)
     begin
	if (rst == 1'b1)
	  overflow <= 0;
	else
	  overflow <= wr_en & full_current;
     end

   // Memory instance
   sdp_ram #(
	     .DEPTH_BASE2 (DEPTH_BASE2), 
             .DATA_WIDTH  (DATA_WIDTH)
	     ) 
   RAM_i (
          .clk   (clk),
          .we    (mywr_en),
          .waddr (wr_addr),
          .din   (data_in),
          .raddr (rd_addr),
          .dout  (data_out)
          );

   // reading empty FIFO will not get valid data, reading pointer doesn't change.
   always @(posedge clk) begin
      if (rst == 1'b1)
	rd_addr <= 0;
      else begin
	 if (rd_en & (~empty_current)) 
	   rd_addr <= rd_addr + 1'b1;
      end
   end

   // active valid indicate valid read data
   always @(posedge clk) begin
      if (rst == 1'b1)
	valid <= 0;
      else
	valid <= rd_en & (~empty_current);
   end
   assign data_out_v = valid;
      
   // underflow being asserted for one cycle means unsuccessful read
   always @(posedge clk) begin
      if (rst == 1'b1)
	underflow <= 0;
      else
	underflow <= rd_en & empty_current;
   end

   // number of valid entries in FIFO
   always @(posedge clk) begin
      if (rst == 1'b1)
	counter <= 0;
      else
	counter <= counter - (rd_en & (~empty_current)) + (wr_en & (~full_current));
   end

   // FIFO empty state machine
   always @(*) begin
      case (empty_current)
	0: 
	  begin
	     if ((counter == 1)&&(rd_en == 1)&&(wr_en == 0))
	       empty_next = 1;
	     else
	       empty_next = 0;
	  end
	1:
	  begin
	     if (wr_en)
	       empty_next = 0;
	     else
	       empty_next = 1;
	  end
      endcase
   end

   always @(posedge clk) begin
      if (rst == 1'b1)
	empty_current <= 1;
      else
	empty_current <= empty_next;
   end
   
   assign empty = empty_current;

   // FIFO full state machine
   always @(*) begin
      case (full_current)
	0: 
	  begin
	     if ((&counter[DEPTH_BASE2-1:0]) & (~counter[DEPTH_BASE2]) & (~rd_en) & (wr_en))
	       full_next = 1;
	     else
	       full_next = 0;
	  end
	1:
	  begin
	     if (rd_en)
	       full_next = 0;
	     else
	       full_next = 1;
	  end
      endcase
   end

   always @(posedge clk) begin
      if (rst == 1'b1)
	full_current <= 0;
      else
	full_current <= full_next;
   end
   
   assign full = full_current;

   // Programmable full signal
   always @(posedge clk) begin
      if (rst == 1'b1)
        prog_full <= 0;
      else begin
	 casex ({(rd_en && ~empty_current), (wr_en && ~full_current)})
           2'b10:        prog_full       <= (counter-1) >= ALMFULL_THRESH;
           2'b01:        prog_full       <= (counter+1) >= ALMFULL_THRESH;
           default:      prog_full       <= prog_full;
	 endcase
      end
   end
   assign alm_full = prog_full;
   
   
endmodule


