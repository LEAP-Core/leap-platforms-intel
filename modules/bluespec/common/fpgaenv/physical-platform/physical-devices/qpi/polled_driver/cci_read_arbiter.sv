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

`include "qpi.vh"

module cci_read_arbiter
  (
    input logic clk,
    input logic resetb,

    input   afu_csr_t           csr,
   
    input   frame_arb_t            frame_writer,
    input   frame_arb_t            frame_reader,

    output  channel_grant_arb_t    read_grant,
   
    output tx_c0_t                 tx0,
    input  logic                   tx0_almostfull
   );


   logic        can_issue;     

   tx_header_t   header;
   logic         rdvalid;

   typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
   
   state_t state;
   state_t next_state;

   // Issue control FSM
   cci_can_issue issue_control( .clk(clk),
                                .resetb(resetb),
                                .almostfull(tx0_almostfull),
                                .can_issue(can_issue),
                                .issue(read_grant.reader_grant | read_grant.writer_grant)
                              );
       
   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb || !csr.afu_en) begin
         state <= FAVOR_FRAME_READER;
      end else begin
         state <= next_state;
      end
   end

   always_comb begin
      if(read_grant.reader_grant)
          next_state = FAVOR_FRAME_WRITER;
      else
          next_state = FAVOR_FRAME_READER;
   end // always_comb begin

   // Set outgoing write control packet.
   always_comb begin
      read_grant.reader_grant = 0;
      read_grant.writer_grant = 0;
      read_grant.status_grant = 0; // status never reads...                                           

      if(frame_reader.read.request && (state == FAVOR_FRAME_READER || !frame_reader.read.request))
         begin
            header = frame_reader.read_header;
            read_grant.reader_grant = can_issue;                                           
         end
      else if(frame_writer.read.request)
        begin
            header = frame_writer.read_header;
            read_grant.writer_grant = can_issue;                                           
        end

      rdvalid = (frame_reader.read.request || frame_writer.read.request) && can_issue;   
   end

   // Register outgoing control packet.
   always_ff @(posedge clk) begin      
      tx0.header      <= header;
      // Should we be setting this while in reset? Who knows...
      tx0.rdvalid     <= rdvalid;      
   end
   
 
   // Some assertions
   always_comb begin
      if(read_grant.reader_grant && read_grant.writer_grant && resetb && ~clk)
        begin
           $display("Double grant of reader %d %d.", read_grant.reader_grant, read_grant.writer_grant);        
           $finish;           
        end
   end
  
endmodule // cci_write_arbiter



