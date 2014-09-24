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

module frame_writer
  #(parameter BUFFER_DEPTH=64, BUFFER_ADDR_WIDTH=6, CACHE_WIDTH=512, UMF_WIDTH=128)
  (
    input logic clk,
    input logic resetb,

    input rx_c0_t rx0,

    input  afu_csr_t           csr,
    output frame_arb_t         frame_writer,
    input  channel_grant_arb_t write_grant,
    input  channel_grant_arb_t read_grant,
   
    // LEAP-facing interface 
    input [UMF_WIDTH-1:0]     tx_data,
    output                    tx_not_full,
    output                    tx_rdy,
    input                     tx_enable
   );

   //=================================================================
   // control FSM
   //=================================================================
   typedef enum logic [2:0] {IDLE, POLL_HEADER, WAIT_HEADER, WRITE, WRITE_FENCE, WRITE_CONTROL} state_t;

   // Addresses are 32 bits and cache line aligned, with 6 bits of zero
   logic [LOG_FRAME_BASE_POINTER - 1:0] frame_base_pointer;
   logic [LOG_FRAME_NUMBER - 1:0]       frame_number;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks;
   logic [3:0]                          idle_count;

   logic [LOG_FRAME_NUMBER - 1:0]       frame_number_next;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_next;

   logic [3:0]                          idle_count_next;

   state_t state;
   state_t next_state;

   
   // Extract frame base pointer from CSRs.
   assign frame_base_pointer = csr.afu_write_frame[QPI_ADDR_SZ+QPI_ADDR_OFFSET:QPI_ADDR_SZ+QPI_ADDR_OFFSET-LOG_FRAME_BASE_POINTER];

   read_metadata_t response_read_metadata;

   assign response_read_metadata = unpack_read_metadata(rx0.header);

   logic frame_header_valid;
   assign frame_header_valid = rx0.rdvalid && ~response_read_metadata.is_read && response_read_metadata.is_header;
   // If header is not valid for reading, then it is valid for writing.
   logic frame_ready_for_write;
   assign frame_ready_for_write = ~header_in_use(rx0.data);

   // We're done with a frame if
   // 1) Idle count expired and data in frame
   // 2) Frame might be full this cycle (whether it is or not is a non-issue).
   logic done_with_writing;
   logic c1, c2, c3;
   assign c1 = (idle_count == 4'hf);
   assign c2 = (frame_chunks != 1);
   assign c3 = (frame_chunks == ((~0) ^ 1'b1));   
   assign done_with_writing = ((idle_count == 4'hf) && (frame_chunks != 1)) || (frame_chunks == ((~0) ^ 1'b1));

   logic data_write_success;   
   assign data_write_success = (state == WRITE) && write_grant.writer_grant;

   logic [UMF_WIDTH-1:0] write_data;
   logic                 write_data_rdy;

   logic deq_rdy;
   logic first_rdy;
   
   logic data_available;
   assign data_available = deq_rdy && first_rdy;

   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb || !csr.afu_en) begin
         state <= IDLE;
      end else begin
         state <= next_state;
      end
   end

//  typedef enum logic [2:0] {IDLE, POLL_HEADER, WAIT_HEADER, WRITE, WRITE_FENCE, WRITE_CONTROL} state_t;
   always_comb begin
      case (state)
        IDLE :
          next_state = POLL_HEADER;
        POLL_HEADER :
          next_state = (read_grant.writer_grant) ? WAIT_HEADER : POLL_HEADER;
        WAIT_HEADER :
          begin
             // No header -or- header not for us.
             next_state = WAIT_HEADER;            
             if(frame_header_valid && frame_ready_for_write)
               begin
                  next_state = WRITE;                  
               end
             else if(frame_header_valid && ~frame_ready_for_write) // we got a header, but it has not been freed by software.
               begin
                  // Need to poll again.
                  next_state = POLL_HEADER;                  
               end
          end // case: WAIT_HEADER
        WRITE:
          begin
             // Read a whole frame 
             next_state = (done_with_writing)?WRITE_FENCE:WRITE;             
          end
        WRITE_FENCE:
          next_state = (write_grant.writer_grant)?WRITE_CONTROL:WRITE_FENCE;
        WRITE_CONTROL:
          next_state = (write_grant.writer_grant)?POLL_HEADER:WRITE_CONTROL;        
        default :
          next_state = state;
      endcase // case (state)
   end // always_comb begin


   // Handle frame management state. Note that frame base pointer is
   // already present in the CSRs, and so need not be registered.
   always_ff @(posedge clk) begin
      frame_number <= frame_number_next;
      frame_chunks <= frame_chunks_next;
      idle_count <= idle_count_next;      
   end

   
   // Update frame number when we tranisiton 
   always_comb begin
      frame_number_next = frame_number;
      if(state == IDLE)
        begin
           frame_number_next = 0;           
        end

      // If we succeed in writing back control we'll move on.
      if(state == WRITE_CONTROL && write_grant.writer_grant)
        begin
           frame_number_next = frame_number + 1;
        end      
   end // always_comb

   always_comb begin
      frame_chunks_next = frame_chunks;
      if(state == POLL_HEADER)
        begin
           // We begin writing one past the first chunk in the frame.
           frame_chunks_next = 1;            
        end
      
      if(data_write_success)
        begin
           $display("Finished writing chunk %d", frame_chunks);           
           frame_chunks_next = frame_chunks + 1;
        end
   end // always_comb

   always_comb begin
      idle_count_next = idle_count + 1;

      // If we have data available set idle count to 0. 
      if(write_data_rdy)
        begin
           idle_count_next = 0;
        end
   end

   tx_header_t read_header;

   read_metadata_t header_read_metadata;

   assign header_read_metadata.is_read   = 1'b0;   
   assign header_read_metadata.is_header = 1'b1;   
   assign header_read_metadata.rob_addr  = 1'b0;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_zero;
   logic header_read_rdy;
   
   assign frame_chunks_zero = 0;
   
   always_comb begin
      read_header = 0;
      read_header.request_type = RdLine;
      read_header.address = {frame_base_pointer,frame_number,frame_chunks_zero}; 
      read_header.mdata = pack_read_metadata(header_read_metadata);      
   end

   tx_header_t write_header;
   // Request a write for a fence, write control, or if we have data.
   // 
   assign frame_writer.write.request = (state == WRITE_FENCE) || (state == WRITE_CONTROL) || (state == WRITE && write_data_rdy);

   always @ (negedge clk)
     begin
        if(state == WRITE_CONTROL)
          $display("FRAME_WRITE of control: %h -> %h ", frame_writer.write_header.address,  frame_writer.data);     
        if(data_write_success)
          $display("FRAME_WRITER: writing out %h -> %h", frame_writer.write_header.address, frame_writer.data);        
     end
  
   always_comb begin
      frame_writer.write_header = 0;
      frame_writer.data = (state==WRITE)?{384'h0,write_data}:{512'hdeadbeef0000}|{515'b0,frame_chunks - 1,1'b1};                                                                                                         
      frame_writer.write_header.request_type = (state == WRITE_FENCE)?WrFence:WrLine;
      frame_writer.write_header.address = {frame_base_pointer, frame_number, (state == WRITE)?frame_chunks:frame_chunks_zero}; 
      frame_writer.write_header.mdata = 0; // No metadata necessary
   end
  
   assign header_read_rdy = state == POLL_HEADER;

   assign frame_writer.read.request = header_read_rdy;
   assign frame_writer.read_header = read_header;
   

   mkSizedFIFOUMF dataBuf(
                      .CLK(clk),
		      .RST_N(resetb),

		      .enq_1(tx_data),
		      .EN_enq(tx_enable),
		      .RDY_enq(tx_rdy),

		      .EN_deq(data_write_success),
		      .RDY_deq(write_data_rdy),

		      .first(write_data),
		      .RDY_first(),

		      .notFull(tx_not_full),
		      .RDY_notFull(),

		      .notEmpty(),
		      .RDY_notEmpty(),

		      .EN_clear(1'b0),
		      .RDY_clear());
        

   
endmodule