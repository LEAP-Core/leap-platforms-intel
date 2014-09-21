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
   
    cci_bus_t cci_bus,
    afu_bus_t afu_bus
   );


   logic        can_issue;
   
   
   typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
   
   state_t state;
   state_t next_state;

   // Issue control FSM
   cci_can_issue issue_control( .clk(clk),
                                .resetb(resetb),
                                .almostfull(cci_bus.tx0.almostfull),
                                .can_issue(can_issue),
                                .issue(afu_bus.frame_reader_grant.read_grant | afu_bus.frame_writer_grant.read_grant)
                              )
       
   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb || !afu_bus.csr.afu_en) begin
         state <= FAVOR_FRAME_READER;
      end else begin
         state <= next_state;
      end
   end

   always_comb begin
      if(afu_bus.frame_reader_grant.read_grant)
          next_state = FAVOR_FRAME_WRITER;
      else
          next_state = FAVOR_FRAME_READER;
   end // always_comb begin

   tx_header_t   header;
   logic         rdvalid;

   // Set outgoing write control packet.
   always_comb begin
      
      if(afu_bus.frame_reader.read.request && (state == FAVOR_FRAME_READER || !afu_bus.frame_reader.read.request))
         begin
            header = afu_bus.frame_reader.readHeader;
            afu_bus.frame_reader_grant.read_grant = can_issue;                                           
         end
      else if(afu_bus.frame_writer.read.request)
        begin
            header = afu_bus.frame_writer.readHeader;
            afu_bus.frame_writer_grant.read_grant = can_issue;                                           
        end
      else
        begin
           afu_bus.frame_reader_grant.read_grant = 0;
           afu_bus.frame_writer_grant.read_grant = 0;                                           
        end
      rdvalid = (afu_bus.frame_reader.read.request || afu_bus.frame_writer.read.request) && can_issue;   
   end

   // Register outgoing control packet.
   always_ff @(posedge clk) begin
      
      cci_bus.tx0.header      <= header;
      // Should we be setting this while in reset? Who knows...
      cci_bus.tx0.rdvalid <= rdvalid;

   end
   
 
   // Some assertions
   always_comb begin
      if(afu_bus.frame_writer_grant.read_grant && afu_bus.frame_reader_grant.read_grant)
        begin
           $display("Double grant.");        
           $finish;           
        end
   end
  
endmodule // cci_write_arbiter



