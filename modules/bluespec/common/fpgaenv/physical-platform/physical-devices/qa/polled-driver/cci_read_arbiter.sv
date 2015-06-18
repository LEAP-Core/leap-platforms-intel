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

`include "qa.vh"

module cci_read_arbiter
  (
    input logic clk,
    input logic resetb,
    input logic lp_initdone,

    input   t_CSR_AFU_STATE        csr,
   
    input   frame_arb_t            status_mgr_req,
    input   frame_arb_t            frame_writer,
    input   frame_arb_t            frame_reader,

    output  channel_grant_arb_t    read_grant,
   
    output tx_c0_t                 tx0,
    input  logic                   tx0_almostfull
   );

   // Only allow issue if the CCI is ready (cci_can_issue) and the accelerator
   // is enabled by software.
   logic         cci_can_issue;
   logic         can_issue;
   assign        can_issue = cci_can_issue && csr.afu_en;

   tx_header_t   header;
   logic         rdvalid;

   typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
   
   state_t state;
   state_t next_state;

   // Issue control FSM
   cci_can_issue issue_control( .clk(clk),
                                .resetb(resetb),
                                .lp_initdone(lp_initdone),
                                .almostfull(tx0_almostfull),
                                .can_issue(cci_can_issue),
                                .issue(read_grant.reader_grant | read_grant.writer_grant)
                              );
       
   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb) begin
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
   always_comb
   begin
      rdvalid = 0;
      read_grant.reader_grant = 0;
      read_grant.writer_grant = 0;
      read_grant.status_grant = 0;

      // Set a default state for header to avoid needlessly muxing with 0
      header = frame_reader.read_header;

      if (frame_reader.read.request && (state == FAVOR_FRAME_READER || !frame_writer.read.request))
      begin
          // header is already set above
          read_grant.reader_grant = can_issue;
          rdvalid = can_issue;
      end
      else if (frame_writer.read.request)
      begin
          header = frame_writer.read_header;
          read_grant.writer_grant = can_issue;
          rdvalid = can_issue;
      end
      else if (status_mgr_req.read.request)
      begin
          header = status_mgr_req.read_header;
          read_grant.status_grant = can_issue;
          rdvalid = can_issue;
      end
   end

   // Register outgoing control packet.
   always_ff @(posedge clk) begin      
      tx0.header      <= header;
      tx0.rdvalid     <= rdvalid && resetb;
   end
  
endmodule // cci_write_arbiter



