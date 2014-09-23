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
// AND ANY EXPRESS
//  OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
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

// The BUFFER_DEPTH and BUFFER_ADDR_WIDTH parameters are not actually
// parameters, since we grabbed modules from bluespec. Probably this
// should be fixed.
module frame_release
  #(parameter BUFFER_DEPTH=64, BUFFER_ADDR_WIDTH=6)
  (
    input logic clk,
    input logic resetb,

    input  afu_csr_t           csr,
    output frame_arb_t         frame_reader,
    input  channel_grant_arb_t write_grant,   

    input [LOG_FRAME_BASE_POINTER - 1:0] frame_base_pointer,
    input release_frame
   
   );

   logic [LOG_FRAME_NUMBER - 1:0]       frame_number_clear; // Used to write back the header for clearing the frame.
   logic [LOG_FRAME_NUMBER - 1:0]       frame_number_clear_next;
   logic [LOG_FRAME_NUMBER - 1:0]       frames_to_be_cleared;
   logic [LOG_FRAME_NUMBER - 1:0]       frames_to_be_cleared_next;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_zero;

   assign frame_chunks_zero = 0;
   
   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb) begin
         frame_number_clear <= 0;
      end else begin
         // If we get a grant, proceed to the next frame.
         frame_number_clear <= frame_number_clear + write_grant.reader_grant;
      end
   end

   always_comb begin
      frames_to_be_cleared_next = frames_to_be_cleared;      
      if(release_frame)
        frames_to_be_cleared_next = frames_to_be_cleared_next + 1;
      if(write_grant.reader_grant)
        frames_to_be_cleared_next = frames_to_be_cleared_next - 1;      
   end
   
   always_ff @(posedge clk) begin
      if (!resetb) begin
         frames_to_be_cleared <= 0;
      end else begin
         frames_to_be_cleared <= frames_to_be_cleared_next;
      end
   end

   tx_header_t write_header;

   assign frame_reader.write.request = ( frames_to_be_cleared > 0);
  
   always_comb begin
      frame_reader.write_header = 0;
      frame_reader.write_header.request_type = WrLine;
      frame_reader.write_header.address = {frame_base_pointer, frame_number_clear, frame_chunks_zero}; 
      frame_reader.write_header.mdata = 0; // No metadata necessary
      frame_reader.data = 1'b0; // only need to set bottom bit.
   end

   
   
   
endmodule