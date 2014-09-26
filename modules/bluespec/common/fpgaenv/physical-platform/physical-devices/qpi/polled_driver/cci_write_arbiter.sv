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

module cci_write_arbiter
  (
    input logic clk,
    input logic resetb,

    input  afu_csr_t           csr,
   
    input   frame_arb_t            frame_writer,
    input   frame_arb_t            frame_reader,
    input   frame_arb_t            status_writer,
    output  channel_grant_arb_t    write_grant,
   
    output tx_c1_t                 tx1,
    input  logic                   tx1_almostfull

   );


   logic        can_issue;

   tx_header_t   header;
   logic [511:0] data;   
   logic         wrvalid;
      
   typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
   
   state_t state;
   state_t next_state;

   // Issue control FSM
   cci_can_issue issue_control( .clk(clk),
                                .resetb(resetb),
                                .almostfull(tx1_almostfull),
                                .can_issue(can_issue),
                                .issue(write_grant.reader_grant | write_grant.writer_grant)
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
      if(write_grant.writer_grant)
          next_state = FAVOR_FRAME_WRITER;
      else
          next_state = FAVOR_FRAME_READER;
   end // always_comb begin


   // Set outgoing write control packet.
   always_comb begin
      write_grant.reader_grant = 0;
      write_grant.writer_grant = 0;
      write_grant.status_grant = 0;                                           

      header  = status_writer.write_header;
      data    = status_writer.data;
      
      if(status_writer.write.request)
        begin
            write_grant.status_grant = can_issue;
        end                                           
      else if(frame_reader.write.request && (state == FAVOR_FRAME_READER || !frame_reader.write.request))
         begin
            header  = frame_reader.write_header;
            data    = frame_reader.data;
            
            write_grant.reader_grant = can_issue;                                           
         end
      else if(frame_writer.write.request)
        begin
            header  = frame_writer.write_header;
            data    = frame_writer.data;
            write_grant.writer_grant = can_issue;                                           
        end

      wrvalid = (frame_reader.write.request || frame_writer.write.request || status_writer.write.request) && can_issue;   
   end

   // Register outgoing control packet.
   always_ff @(posedge clk) begin      
      tx1.header      <= header;
      // Should we be setting this while in reset? Who knows...
      tx1.wrvalid <= wrvalid;
      tx1.data    <= data;
   end

   // Some assertions
   always_comb begin
      if(write_grant.writer_grant && write_grant.reader_grant && resetb && ~clk)
        begin
           $display("Double grant of reader %d %d.", write_grant.reader_grant, write_grant.writer_grant);        
           $finish;           
        end
   end
   
endmodule // cci_write_arbiter





