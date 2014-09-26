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

module status_writer
  (
    input logic clk,
    input logic resetb,

    input  afu_csr_t           csr,
    output frame_arb_t         status_writer,
    input  channel_grant_arb_t write_grant
   );

   typedef enum {IDLE, DONE} state_t;
   state_t state;
   state_t next_state;
     
   bit [31:0]   status_array [15:0];
   
   logic [511:0] status;
   assign status_array[3] = 32'haced0003;
   assign status_array[2] = 32'haced0002;
   assign status_array[1] = 32'haced0001;
   assign status_array[0] = 32'haced0000;

   genvar        i;

   generate
      for (i = 0; i < 16; i++) begin : gen_status
         assign status[32*(i+1)-1:32*i] = status_array[i];        
      end
   endgenerate
   
   
      
   //=================================================================
   // FSM
   //=================================================================

   always_ff @(posedge clk) begin
      if (!resetb) begin
         state <= IDLE;
      end else begin
         state <= next_state;
      end
   end

   always_comb begin
      case (state)
        IDLE :
          next_state = (write_grant.status_grant)?DONE:IDLE;
        default :
          next_state = state;
      endcase // case (state)
   end // always_comb begin


   //=================================================================
   // create CCI Tx1 transaction
   //=================================================================
   logic [9:0] offset;
   logic [511:0] data;

   assign status_writer.write.request = (state == IDLE) && csr.afu_dsm_base_valid;

   always@(negedge clk)
     begin
        if(QPI_DRIVER_DEBUG)
         begin  
            if(status_writer.write.request)
              $display("Status writer attempts to write 0x%h to CL 0x%h", status_writer.data, status_writer.write_header.address);
            if(write_grant.status_grant)
              $display("Status writer write request granted");        
         end
     end
   
   always_comb begin
      offset = 0;
      data = status;

      status_writer.write_header = 0;
      status_writer.write_header.request_type = WrLine;
      status_writer.write_header.address = dsm_offset2addr(0, csr.afu_dsm_base);
      status_writer.data = status;      
   end
   
endmodule // status_writer
