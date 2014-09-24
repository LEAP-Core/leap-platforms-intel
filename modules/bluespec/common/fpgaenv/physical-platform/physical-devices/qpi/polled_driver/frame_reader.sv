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
module frame_reader
  #(parameter BUFFER_DEPTH=64, BUFFER_ADDR_WIDTH=6, CACHE_WIDTH=512, UMF_WIDTH=128)
  (
    input logic clk,
    input logic resetb,
   
    input rx_c0_t rx0,
   
    input  afu_csr_t           csr,
    output frame_arb_t         frame_reader,
    input  channel_grant_arb_t read_grant,
    input  channel_grant_arb_t write_grant,
   
    output [UMF_WIDTH-1:0]    rx_data,   
    output                    rx_not_empty,
    output                    rx_rdy,
    input                     rx_enable
   
   );

   //=================================================================
   // control FSM
   //=================================================================

   // IDLE            - Fresh 
   // POLL_HEADER     - Issue a request for frame header
   // WAIT_HEADER     - Wait for frame header to return
   // READ            - Issue read requests
   // FRAME_COMPLETE  - Wait for read requests to return (really, we want a read fence? Worth a test at some point)
   
   typedef enum logic [2:0] {IDLE, POLL_HEADER, WAIT_HEADER, READ, FRAME_COMPLETE} state_t;

   // Addresses are 32 bits and cache line aligned, with 6 bits of zero
   logic [LOG_FRAME_BASE_POINTER - 1:0] frame_base_pointer;
   logic [LOG_FRAME_NUMBER - 1:0]       frame_number;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_total;

   logic [LOG_FRAME_NUMBER - 1:0]       frame_number_next;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_next;
   logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_total_next;

   // Extract frame base pointer from CSRs.
   assign frame_base_pointer = csr.afu_read_frame[QPI_ADDR_SZ+QPI_ADDR_OFFSET:QPI_ADDR_SZ+QPI_ADDR_OFFSET-LOG_FRAME_BASE_POINTER];
      
   state_t state;
   state_t next_state;


   read_metadata_t response_read_metadata;

   assign response_read_metadata = unpack_read_metadata(rx0.header);
   
   // FSM state
   always_ff @(posedge clk) begin
      if (!resetb || !csr.afu_en) begin
         state <= IDLE;
      end else begin
         state <= next_state;
      end
   end

   logic frame_header_valid;
   logic frame_ready_for_read;

   
   assign frame_header_valid = rx0.rdvalid && response_read_metadata.is_read && response_read_metadata.is_header;
   assign frame_ready_for_read = header_in_use(rx0.data);

   assign data_read_accepted = read_grant.reader_grant && (state == READ);                                           
   assign last_data_read_accepted = data_read_accepted && (frame_chunks_total == frame_chunks);
   
   always_comb begin
      case (state)
        IDLE :
          next_state = POLL_HEADER;
        POLL_HEADER :
          next_state = (read_grant.reader_grant) ? WAIT_HEADER : POLL_HEADER;
        WAIT_HEADER :
          begin
             // No header or header was not for me.
             next_state = WAIT_HEADER;            
             if(frame_header_valid && frame_ready_for_read)
               begin                  
                  next_state = READ;                  
               end
             else if(frame_header_valid && ~frame_ready_for_read)
               begin
                  // Need to poll again.
                  next_state = POLL_HEADER;                  
               end
          end // case: WAIT_HEADER
        READ:
          begin
             // Read a whole frame 
             next_state = (last_data_read_accepted)?FRAME_COMPLETE:READ;             
          end
        FRAME_COMPLETE:
          next_state = POLL_HEADER;        
        default :
          next_state = state;
      endcase // case (state)
   end // always_comb begin

   
   // Handle frame management state. Note that frame base pointer is
   // already present in the CSRs, and so need not be registered.
   always_ff @(posedge clk) begin
      frame_number <= frame_number_next;
      frame_chunks <= frame_chunks_next;
   end

   always_ff @(posedge clk) begin
      frame_chunks_total <= frame_chunks_total_next;
   end

   always_comb begin
      frame_chunks_total_next = frame_chunks_total;
      if(state != READ)
        begin
           frame_chunks_total_next = header_chunks(rx0.data);
        end
   end
   
   // Update frame number when we tranisiton 
   always_comb begin
      frame_number_next = frame_number;
      if(state == IDLE)
        begin
           frame_number_next = 0;           
        end
  
      if(state == FRAME_COMPLETE)
        begin
           frame_number_next = frame_number + 1;
        end      
   end // always_comb

   always_comb begin
      frame_chunks_next = frame_chunks;
      if(state == IDLE || state == FRAME_COMPLETE)
        begin
           frame_chunks_next = 0;           
        end

      if(state == READ && read_grant.reader_grant)
        begin
           frame_chunks_next = frame_chunks + 1;
        end

      if(state == WAIT_HEADER && frame_header_valid && frame_ready_for_read)
        begin
           frame_chunks_next = frame_chunks + 1;
        end      
   end
   
   // Logic for dealing with returning data response.
   logic incoming_read_valid;
   logic scoreboard_ready;

   assign incoming_read_valid = rx0.rdvalid && response_read_metadata.is_read && !response_read_metadata.is_header;

   always@(negedge clk)
     begin
         if(rx0.data != 0)
          begin
             $display("Frame reader got a response: header %h data %h (low: %h)", rx0.header, rx0.data, rx0.data[LOG_FRAME_CHUNKS:0]);
             $display("Frame reader got a response: decode header ready %h chunks %h", frame_ready_for_read, frame_chunks_total_next);
             $display("Frame reader got a response: is_read %h is_header %h", response_read_metadata.is_read, response_read_metadata.is_header);
          end
        if(state == READ)
          begin
             $display("Transition to READ!!!");             
          end        
     end
   
   logic [CACHE_WIDTH-1:0]       read_line;
   logic                         read_line_score_rdy;
   logic                         read_line_marsh_rdy;
   logic                         read_line_en;
   
   logic [BUFFER_ADDR_WIDTH-1:0] scoreboard_slot_id;
   logic                         scoreboard_slot_rdy;
   logic                         scoreboard_slot_en;

   tx_header_t read_header;

   read_metadata_t data_read_metadata;
   read_metadata_t header_read_metadata;

   
   always_comb begin
      read_header = 0;
      read_header.request_type = RdLine;
      read_header.address = {frame_base_pointer,frame_number,frame_chunks}; 
      read_header.mdata = (state == READ) ? pack_read_metadata(data_read_metadata) : pack_read_metadata(header_read_metadata);      
   end


   logic data_read_rdy;
   logic header_read_rdy;
   logic enqueue_last;
   logic frame_release_count_up;
   

   assign data_read_rdy = scoreboard_slot_rdy && state == READ;
   assign header_read_rdy = state == POLL_HEADER;

   assign frame_reader.read.request = data_read_rdy || header_read_rdy;
   assign frame_reader.read_header = read_header;
                           
   assign data_read_metadata.is_read   = 1'b1;   
   assign data_read_metadata.is_header = 1'b0;   
   assign data_read_metadata.rob_addr  = {0,scoreboard_slot_id};

   assign header_read_metadata.is_read   = 1'b1;   
   assign header_read_metadata.is_header = 1'b1;   
   assign header_read_metadata.rob_addr  = {0,scoreboard_slot_id};

   assign release_frame = frame_release_count_up && rx_enable;
   
   assign read_line_en = read_line_score_rdy && read_line_marsh_rdy;

   always_comb begin
      if(incoming_read_valid && !scoreboard_ready)
        begin
           $display("Failed to place incoming data into scoreboard");           
           $finish;           
        end
   end
   
   // modules for interfacing with  downstream code
   mkScoreboardQPI scoreboard(.CLK(clk),
		   .RST_N(resetb),

		   .EN_enq(data_read_accepted),
		   .enq(scoreboard_slot_id),
		   .RDY_enq(scoreboard_slot_rdy),

		   .setValue_id(response_read_metadata.rob_addr[BUFFER_ADDR_WIDTH-1:0]),
		   .setValue_data(rx0.data),
		   .EN_setValue(incoming_read_valid),
		   .RDY_setValue(scoreboard_ready), // We had better be ready.

  	           .first(read_line),
		   .RDY_first(),

		   .EN_deq(rx_enable),
		   .RDY_deq(rx_rdy),

		   .notFull(),
		   .RDY_notFull(),

		   .notEmpty(rx_not_empty),
		   .RDY_notEmpty(),

		   .deqEntryId(),
		   .RDY_deqEntryId());

   assign rx_data = read_line[UMF_WIDTH-1:0];
                   
   mkSizedFIFOQPI ctrlFIFO(.CLK(clk),
		      .RST_N(resetb),

		      .enq_1(last_data_read_accepted),
		      .EN_enq(data_read_accepted),
		      .RDY_enq(), // Since this queue is the same size as the scoreboard, we don't require teh ready.

		      .EN_deq(rx_enable),
		      .RDY_deq(),

		      .first(frame_release_count_up),
		      .RDY_first(),

		      .notFull(),
		      .RDY_notFull(),

		      .notEmpty(),
		      .RDY_notEmpty(),

		      .EN_clear(1'b0),
		      .RDY_clear());

   frame_arb_t         frame_reader_release;
   assign frame_reader.write_header  = frame_reader_release.write_header;
   assign frame_reader.write.request = frame_reader_release.write.request;
   assign frame_reader.data          = frame_reader_release.data;
      
   frame_release releaseMod(
                      .clk(clk),
                      .resetb(resetb),
   
                      .csr(csr),
                      .frame_reader(frame_reader_release),
                      .write_grant(write_grant),   

                      .frame_base_pointer(frame_base_pointer),
                      .release_frame(release_frame)
   );

   
endmodule