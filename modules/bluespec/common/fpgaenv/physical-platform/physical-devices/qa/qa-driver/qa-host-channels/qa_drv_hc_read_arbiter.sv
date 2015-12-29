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

`include "qa_drv_hc.vh"

module qa_drv_hc_read_arbiter
  (
    input logic clk,
    input logic reset_n,

    input   t_CSR_AFU_STATE        csr,
   
    input   t_FRAME_ARB            status_mgr_req,
    input   t_FRAME_ARB            frame_writer,
    input   t_FRAME_ARB            frame_reader,

    output  t_CHANNEL_GRANT_ARB    read_grant,
   
    output t_TX_C0                 tx0,
    input  logic                   tx0_almostfull
   );

   // Only allow issue if the CCI is ready (cci_can_issue) and the accelerator
   // is enabled by software.
   logic         cci_can_issue;
   logic         can_issue;
   assign        can_issue = cci_can_issue && csr.afu_en;

   t_TX_HEADER   header;
   logic         rdvalid;

   typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
   
   state_t state;
   state_t next_state;

   // Issue control FSM
   qa_drv_hc_can_issue issue_control
     (
      .clk(clk),
      .reset_n(reset_n),
      .almostfull(tx0_almostfull),
      .can_issue(cci_can_issue),
      .issue(read_grant.readerGrant | read_grant.writerGrant)
      );
       
   // FSM state
   always_ff @(posedge clk) begin
      if (!reset_n) begin
         state <= FAVOR_FRAME_READER;
      end else begin
         state <= next_state;
      end
   end

   always_comb begin
      if(read_grant.readerGrant)
          next_state = FAVOR_FRAME_WRITER;
      else
          next_state = FAVOR_FRAME_READER;
   end // always_comb begin

   // Set outgoing write control packet.
   always_comb
   begin
      rdvalid = 0;
      read_grant.canIssue = can_issue;
      read_grant.readerGrant = 0;
      read_grant.writerGrant = 0;
      read_grant.statusGrant = 0;

      // Set a default state for header to avoid needlessly muxing with 0
      header = frame_reader.readHeader;

      if (frame_reader.read.request && (state == FAVOR_FRAME_READER || !frame_writer.read.request))
      begin
          // header is already set above
          read_grant.readerGrant = can_issue;
          rdvalid = can_issue;
      end
      else if (frame_writer.read.request)
      begin
          header = frame_writer.readHeader;
          read_grant.writerGrant = can_issue;
          rdvalid = can_issue;
      end
      else if (status_mgr_req.read.request)
      begin
          header = status_mgr_req.readHeader;
          read_grant.statusGrant = can_issue;
          rdvalid = can_issue;
      end
   end

   // Register outgoing control packet.
   always_ff @(posedge clk) begin      
      tx0.header      <= header;
      tx0.rdvalid     <= rdvalid && reset_n;
   end
  
endmodule // cci_write_arbiter



