// ***************************************************************************
//                               INTEL CONFIDENTIAL
//
//        Copyright (C) 2008-2011 Intel Corporation All Rights Reserved.
//
// The source code contained or described herein and all  documents related to
// the  source  code  ("Material")  are  owned  by  Intel  Corporation  or its
// suppliers  or  licensors.    Title  to  the  Material  remains  with  Intel
// Corporation or  its suppliers  and licensors.  The Material  contains trade
// secrets  and  proprietary  and  confidential  information  of  Intel or its
// suppliers and licensors.  The Material is protected  by worldwide copyright
// and trade secret laws and treaty provisions. No part of the Material may be
// used,   copied,   reproduced,   modified,   published,   uploaded,  posted,
// transmitted,  distributed,  or  disclosed  in any way without Intel's prior
// express written permission.
//
// No license under any patent,  copyright, trade secret or other intellectual
// property  right  is  granted  to  or  conferred  upon  you by disclosure or
// delivery  of  the  Materials, either expressly, by implication, inducement,
// estoppel or otherwise.  Any license under such intellectual property rights
// must be express and approved by Intel in writing.
//
// Engineer:            Pratik Marolia
// Create Date:         Fri Jul 29 14:45:20 PDT 2011
// Module Name:         gfifo.v
// Project:             NLB AFU 
// Description:
//
// ***************************************************************************
// gfifo.v: Generic FIFO using gram_sdp
// qigang.wang@intel.com Copyright Intel 2008
// Created 2008Oct17
// 
// Generic FIFO instantiates gram with mode 2. It provides a simple FIFO interface.
// This interface contains write port, read port and FIFO status information.
// 
// GFIFO has the ability to detect some errors and protect itself from being
// misused. Writing a full FIFO will assert overflow flag and incoming data gets
// discarded. Reading an empty FIFO will assert underflow flag. In both cases,
// FIFO's internal pointers will keep unchanged. However, others blocks
// should send correct wr_en and rd_en instead of relying on this feature.
// Overflow and underflow should be regarded as errors.
//  
// A successful read data is indicated by active valid. 
//  
// Programmable full feature is optional, which can be enabled by overriding PROG_FULL_THRESH.
//  
// empty, full and prog_full are registered outputs.
// 
// Timing diagram of read FIFO interface:
//         __      ____      ____      ____
//    clk    \____/    \____/    \____/
//             ________
//   rd_en ___/        \___________________
//                    _________
// rd_data <XXXXXXXXX<__DATA___><XXXXXXXXXX
//                    __________
//  valid  __________/          \__________
//
// You can override parameters to customize FIFO.
//

// `include "dpi_global.vh"
`include "ase_global.vh"

module gfifo_v (rst_x,       // input   reset, reset polarity defined by SYNC_RESET_POLARITY
                clk,         // input   clock
                wr_data,     // input   write data with configurable width
                wr_en,       // input   write enable
                overflow,    // output  overflow being asserted indicates one incoming data gets discarded
                rd_en,       // input   read enable
                rd_data,     // output  read data with configurable width
                valid,       // output  active valid indicate valid read data
                underflow,   // output  underflow being asserted indicates one unsuccessfully read
                empty,       // output  FIFO empty
                full,        // output  FIFO full
                count,       // output  FIFOcount
                prog_full);  // output  configurable programmable full/ almost full

parameter BUS_SIZE_ADDR=5;      // number of bits of address bus
parameter BUS_SIZE_DATA=16;     // number of bits of data bus
parameter RAM_STYLE=`GRAM_AUTO; // GRAM_AUTO, GRAM_BLCK, GRAM_DIST
parameter PROG_FULL_THRESH=0;   // prog_full will be asserted if there are more entries than PROG_FULL_THRESH 

input rst_x;
input clk;
input [BUS_SIZE_DATA-1:0] wr_data;
input wr_en;
output overflow;
input rd_en;
output [BUS_SIZE_DATA-1:0] rd_data;
output valid;
output underflow;
output empty;
output full;
output [BUS_SIZE_ADDR-1:0] count;
output prog_full;

reg overflow;
reg valid;
reg underflow;
reg prog_full;

wire mywr_en;
wire [BUS_SIZE_ADDR-1:0] count;

reg empty_current;
reg empty_next;
reg full_current;
reg full_next;
reg [BUS_SIZE_ADDR-1:0] rd_addr;
reg [BUS_SIZE_ADDR-1:0] wr_addr;
reg [BUS_SIZE_ADDR:0] counter;

// discard incoming data when FIFO is full
assign mywr_en = wr_en & (~full_current);
assign count   = counter [BUS_SIZE_ADDR-1:0];

// writing pointer doesn't change when overflow
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    wr_addr <= 0;
  else begin
    if (mywr_en) 
      wr_addr <= wr_addr + 1'b1;
  end
end

// overflow being asserted for one cycle means one incoming data was discarded
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    overflow <= 0;
  else
    overflow <= wr_en & full_current;
end

// instantiate gram with mode 1
gram_sdp #(.BUS_SIZE_ADDR(BUS_SIZE_ADDR), 
          .BUS_SIZE_DATA(BUS_SIZE_DATA),
          .RAM_MODE(1), 
          .RAM_STYLE(RAM_STYLE)) 
        m_RAM (
          .clk(clk),
          .we(mywr_en),
          .waddr(wr_addr),
          .din(wr_data),
          .raddr(rd_addr),
          .dout(rd_data)
        );

// reading empty FIFO will not get valid data, reading pointer doesn't change.
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    rd_addr <= 0;
  else begin
    if (rd_en & (~empty_current)) 
      rd_addr <= rd_addr + 1'b1;
  end
end

// active valid indicate valid read data
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    valid <= 0;
  else
    valid <= rd_en & (~empty_current);
end

// underflow being asserted for one cycle means unsuccessful read
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    underflow <= 0;
  else
    underflow <= rd_en & empty_current;
end

// number of valid entries in FIFO
always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    counter <= 0;
  else
    counter <= counter - (rd_en & (~empty_current)) + (wr_en & (~full_current));
end

// FIFO empty state machine
always @(*)
begin
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

always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    empty_current <= 1;
  else
    empty_current <= empty_next;
end

assign empty = empty_current;

// FIFO full state machine
always @(*)
begin
  case (full_current)
    0: 
    begin
      if ((&counter[BUS_SIZE_ADDR-1:0]) & (~counter[BUS_SIZE_ADDR]) & (~rd_en) & (wr_en))
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

always @(posedge clk)
begin
  if (rst_x == `SYNC_RESET_POLARITY)
    full_current <= 0;
  else
    full_current <= full_next;
end

assign full = full_current;

// generate programmable full only when required
generate if (PROG_FULL_THRESH)
  begin : GEN_ENABLE_PROG_FULL
    always @(posedge clk)
    begin
      if (rst_x == `SYNC_RESET_POLARITY)
        prog_full <= 0;
      else begin
        casex ({(rd_en && ~empty_current), (wr_en && ~full_current)})
                2'b10:        prog_full       <= (counter-1) >= PROG_FULL_THRESH;
                2'b01:        prog_full       <= (counter+1) >= PROG_FULL_THRESH;
                default:      prog_full       <= prog_full;
        endcase
      end
    end
  end
endgenerate

endmodule
