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
// Module Name:         sbv_gfifo.v
// Project:             NLB AFU 
// Description:
//
// ***************************************************************************

//-----------------------------------------------------------------
//  (C) Copyright Intel Corporation, 2008.  All Rights Reserved.
//-----------------------------------------------------------------
//
//  
//---------------------------------------------------------------------------------------------------------------------------------------------------
//                                        sbv_gfifo with Read Store & Read-Write forwarding
//---------------------------------------------------------------------------------------------------------------------------------------------------
// 22-4-2010 : Renamed cci_hdr_fifo into sb_gfifo
// 26-4-2011 : Derived sbv_gfifo from sb_gfifo.
//	       The read engine in the fifo presents valid data on output ports. When data out is used, rdack should be asserted.
//	       This is different from a traditional fifo where the fifo pops out a new data in response to a rden in the previous clk.
//	       Instead this fifo presents the valid data on output port & expects a rdack in the same clk when data is consumed.
//
// Read latency  = 1
// Write latency = 1
//
// Bypass Logic = 0     - illegal to read an empty fifo
//              = 1     - reading an empty fifo, returns the data from the write data port (fifo_din). 1 clk delay
//
// Read Store   = 0     - fifo_dout valid for only 1 clock after read enable
//              = 1     - fifo_dout stores the last read value. The value chanegs on next fifo read.
//
// Full thresh          - value should be less than/ euqual to 2**DEPTH_BASE2. If # entries more than threshold than fifo_almFull is set
//
//

// `include "dpi_global.vh"
`include "ase_global.vh"

module sbv_gfifo    #(parameter DATA_WIDTH      =51,
                      parameter DEPTH_BASE2     =3, 
                      parameter BYPASS_LOGIC    =0,          // Read-write forwarding, enabling this adds significant delay on write control path
                      parameter FULL_THRESH     =7,          // fifo_almFull will be asserted if there are more entries than FULL_THRESH
                      parameter RAM_STYLE       =`GRAM_AUTO) // GRAM_AUTO, GRAM_BLCK, GRAM_DIST
                (
                Resetb,            //Active low reset
                Clk,               //global clock
                fifo_din,          //Data input to the FIFO tail
                fifo_wen,          //Write to the tail
                fifo_rdack,        //Read ack, pop the next entry
                                   //--------------------- Output  ------------------
                fifo_dout,         //FIFO read data out     
                fifo_dout_v,       //FIFO data out is valid 
                fifo_empty,        //FIFO is empty
                fifo_full,         //FIFO is full
                fifo_count,        //Number of entries in the FIFO
                fifo_almFull       //fifo_count > FULL_THRESH
                ); 

input                    Resetb;           // Active low reset
input                    Clk;              // global clock    
input  [DATA_WIDTH-1:0]  fifo_din;         // FIFO write data in
input                    fifo_wen;         // FIFO write enable
input                    fifo_rdack;       // Read ack, pop the next entry

output [DATA_WIDTH-1:0]  fifo_dout;        // FIFO read data out
output                   fifo_dout_v;      // FIFO data out is valid 
output                   fifo_empty;       // set when FIFO is empty
output                   fifo_full;        // set if Fifo full
output [DEPTH_BASE2-1:0] fifo_count;       // Number of entries in the fifo
output                   fifo_almFull;
//------------------------------------------------------------------------------------

localparam               READ_STORE = 1;	// Holds output data until next rdack

reg                      fifo_wen_x;
reg    [DATA_WIDTH-1:0]  rd_data_q;
reg                      bypass_en;
reg                      rd_saved;
reg                      fifo_dout_v;

wire                     fifo_almFull;
wire                     fifo_empty_x;
wire   [DATA_WIDTH-1:0]  rd_data;
wire   [DATA_WIDTH-1:0]  fifo_din;
wire                     fifo_ren 	= fifo_rdack 
                                         |!fifo_dout_v;
wire                     fifo_ren_x     = fifo_ren & !fifo_empty_x;
wire   [DATA_WIDTH-1:0]  fifo_dout      = (BYPASS_LOGIC & bypass_en)
                                         |(READ_STORE   & rd_saved ) ? rd_data_q
                                                                     : rd_data;
wire			 fifo_empty 	= fifo_empty_x 
                                         &!fifo_dout_v;
   
always @(*)
begin
        if(BYPASS_LOGIC)        // Data forwarding Enabled - reading an empty fifo, returns the data from the write data port (fifo_din)
                fifo_wen_x = fifo_wen & !(fifo_empty_x & fifo_ren);
        else                    // Data forwarding Disabled
                fifo_wen_x = fifo_wen;
end

always @(posedge Clk)
begin
        if(!Resetb)
          begin
                fifo_dout_v <= 0;
          end
        else
          begin
                case(1)    // synthesis parallel_case
                        (BYPASS_LOGIC & fifo_wen & fifo_ren & fifo_empty_x): fifo_dout_v <= 1;
                        (fifo_ren & !fifo_empty_x)                         : fifo_dout_v <= 1;
                        (!fifo_ren)                                        : fifo_dout_v <= 1;
                        default                                            : fifo_dout_v <= 0;
                endcase

          end // Resetb
          
                if( BYPASS_LOGIC                               // Allows reading an empty fifo
                  & fifo_empty_x                               // Fifo is transparent, it forwards the input data
                  & fifo_ren )                                 // to the output data port. 1 clk delay
                  begin
                        rd_data_q        <= fifo_din;
                        bypass_en        <= 1;
                  end
                 else
                 begin
                        bypass_en        <= 0;
                        if(READ_STORE)
                        begin                                 
                                rd_data_q    <= fifo_dout;
                        end
                  end

                  if ( READ_STORE
                     & fifo_ren  )rd_saved   <= 0;
                  else            rd_saved   <= 1;

          
end

//---------------------------------------------------------------------------------------------------------------------
//              Module instantiations
//---------------------------------------------------------------------------------------------------------------------

wire    fifo_overflow;
wire    fifo_underflow;
wire    fifo_valid;

gfifo_v         #( .BUS_SIZE_ADDR   (DEPTH_BASE2),     // number of bits of address bus
                   .BUS_SIZE_DATA   (DATA_WIDTH ),     // number of bits of data bus
                   .PROG_FULL_THRESH(FULL_THRESH),     // prog_full will be asserted if there are more entries than PROG_FULL_THRESH 
                   .RAM_STYLE       (RAM_STYLE  ))     // GRAM_AUTO, GRAM_BLCK, GRAM_DIST
                gfifo_v
                (                
                .rst_x    (Resetb),           // input   reset, reset polarity defined by SYNC_RESET_POLARITY
                .clk      (Clk),              // input   clock
                .wr_data  (fifo_din),         // input   write data with configurable width
                .wr_en    (fifo_wen_x),       // input   write enable
                .overflow (fifo_overflow),    // output  overflow being asserted indicates one incoming data gets discarded
                .rd_en    (fifo_ren_x),       // input   read enable
                .rd_data  (rd_data),          // output  read data with configurable width
                .valid    (fifo_valid),       // output  active valid indicate valid read data
                .underflow(fifo_underflow),   // output  underflow being asserted indicates one unsuccessfully read
                .empty    (fifo_empty_x),     // output  FIFO empty
                .full     (fifo_full),        // output  FIFO full
                .count    (fifo_count),       // output  FIFOcount
                .prog_full(fifo_almFull)
                );

//---------------------------------------------------------------------------------------------------------------------
//              Error Logic
//---------------------------------------------------------------------------------------------------------------------
//synthesis translate_off
always @(*)
begin
        if(BYPASS_LOGIC==0)
        if(fifo_underflow)      $display("%m ERROR: fifo underflow detected");
                
        if(fifo_overflow)       $display("%m ERROR: fifo overflow detected");
end
//synthesis translate_on
endmodule 



