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

module status_writer
  (
    input logic clk,
    input logic resetb,

    input  afu_csr_t           csr,
    output frame_arb_t         status_writer,
    input  channel_grant_arb_t write_grant,
   
    input t_AFU_DEBUG_RSP      dbg_frame_reader
   );

   typedef enum {STATE_INIT, STATE_IDLE, STATE_DEBUG} state_t;
   state_t state;
   state_t next_state;
     

   //
   // AFU ID is used at the beginning of a run to tell the host the FPGA
   // is alive.
   //
   bit [31:0]   afu_id_array [15:0];
   
   logic [511:0] afu_id;
   assign afu_id_array[3] = 32'haced0003;
   assign afu_id_array[2] = 32'haced0002;
   assign afu_id_array[1] = 32'haced0001;
   assign afu_id_array[0] = 32'haced0000;

   genvar i;
   generate
      for (i = 0; i < 16; i++) begin : gen_afu_id
         assign afu_id[32*(i+1)-1:32*i] = afu_id_array[i];        
      end
   endgenerate
   
   
   //
   // Debugging state dump, triggered by CSR_AFU_TRIGGER_DEBUG.
   //

   // Request (from the CSR write)
   t_AFU_DEBUG_REQ debug_req;
   // Response (muxed from other modules below)
   t_AFU_DEBUG_RSP debug_rsp;
   // The full message to be written to DSM line 0.
   logic [511:0] debug_rsp_line;
   assign debug_rsp_line = {debug_req, debug_rsp};

   // What debug info to write?
   always_comb begin
      case (debug_req)
        1:
          debug_rsp = dbg_frame_reader;
        default:
          debug_rsp = dbg_frame_reader;
      endcase
   end

   // Grab the index of debugging requests.  It is illegal in the debugging
   // protocol to trigger a new request before the previous one is done,
   // making this logic simple.
   always_ff @(posedge clk) begin
      if (csr.afu_trigger_debug != 0) begin
         debug_req <= csr.afu_trigger_debug;
      end
   end

      
   //=================================================================
   // FSM
   //=================================================================

   always_ff @(posedge clk) begin
      if (!resetb) begin
         state <= STATE_INIT;
      end else begin
         state <= next_state;
      end
   end

   always_comb begin
      next_state = state;

      // Very simple protocol.  Only one thing may be active at a time.
      // No other requests may be processed while in STATE_INIT.  No new
      // DEBUG requests will be noticed until the current one completes.
      if (write_grant.status_grant) begin
         next_state = STATE_IDLE;
      end
      else if (csr.afu_trigger_debug != 0) begin
         next_state = STATE_DEBUG;
      end
   end

   //=================================================================
   // create CCI Tx1 transaction
   //=================================================================
   logic [9:0] offset;
   logic [511:0] data;

   assign status_writer.write.request = (state != STATE_IDLE) && csr.afu_dsm_base_valid;

   always@(negedge clk)
     begin
        if(QA_DRIVER_DEBUG)
         begin  
            if(status_writer.write.request)
              $display("Status writer attempts to write 0x%h to CL 0x%h", status_writer.data, status_writer.write_header.address);
            if(write_grant.status_grant)
              $display("Status writer write request granted");        
         end
     end
   
   always_comb begin
      // All writes are to DSM line 0
      offset = 0;
      // Write either a line of debug data or the AFU ID.
      data = (state == STATE_DEBUG) ? debug_rsp_line : afu_id;

      status_writer.write_header = 0;
      status_writer.write_header.request_type = WrLine;
      status_writer.write_header.address = dsm_offset2addr(offset, csr.afu_dsm_base);
      status_writer.data = data;
   end
   
endmodule // status_writer
