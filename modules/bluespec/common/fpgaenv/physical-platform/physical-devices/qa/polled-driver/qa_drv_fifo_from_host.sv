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

`include "qa.vh"

module qa_drv_fifo_from_host
  #(parameter BUFFER_DEPTH=64,
    BUFFER_ADDR_WIDTH=6,
    CACHE_WIDTH=512,
    UMF_WIDTH=128)
    (input logic clk,
     input logic resetb,

     input rx_c0_t rx0,

     input  t_CSR_AFU_STATE     csr,
     output frame_arb_t         frame_reader,
     input  channel_grant_arb_t read_grant,
     input  channel_grant_arb_t write_grant,

     output [UMF_WIDTH-1:0]     rx_data,
     output                     rx_rdy,
     input                      rx_enable,

     output t_AFU_DEBUG_RSP     dbg_fifo_from_host,
     output t_AFU_DEBUG_RSP     dbg_frame_release
    );

    //
    // Control FSM:
    //
    //   IDLE            - Fresh
    //   POLL_HEADER     - Issue a request for frame header
    //   WAIT_HEADER     - Wait for frame header to return
    //   READ            - Issue read requests
    //   FRAME_COMPLETE  - Wait for read requests to return (really, we want a read fence? Worth a test at some point)
    //
    typedef enum logic [2:0]
    {
        IDLE,
        POLL_HEADER,
        WAIT_HEADER,
        READ,
        FRAME_COMPLETE
    }
    t_STATE;

    // Addresses are 32 bits and cache line aligned, with 6 bits of zero
    logic [LOG_FRAME_BASE_POINTER - 1:0] frame_base_pointer;
    logic [LOG_FRAME_NUMBER - 1:0]       frame_number;
    logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks;
    logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_total;

    logic [LOG_FRAME_NUMBER - 1:0]       frame_number_next;
    logic [LOG_FRAME_CHUNKS - 1:0]       frame_chunks_next;

    logic frame_header_valid;
    logic frame_ready_for_read;

    t_STATE state;
    t_STATE next_state;

    // Logic for dealing with returning data response.
    logic incoming_read_valid;

    logic [CACHE_WIDTH-1:0]       read_line;
    logic [CACHE_WIDTH-1:0]       read_line_last;

    logic [BUFFER_ADDR_WIDTH-1:0] scoreboard_slot_id;
    logic                         scoreboard_slot_rdy;
    logic                         scoreboard_slot_en;

    logic data_read_rdy;
    logic header_read_rdy;
    logic enqueue_last;

    // Code related to frame release
    logic frame_release_count_up;


    tx_header_t read_header;
    read_metadata_t response_read_metadata;
    read_metadata_t data_read_metadata;
    read_metadata_t header_read_metadata;

    frame_arb_t         frame_reader_release;

    // Ok to return a new frame if one is ready and the release engine can
    // handle another request.
    logic scoreboard_not_empty;
    logic can_req_frame_release;
    assign rx_rdy = scoreboard_not_empty && can_req_frame_release;

    // Extract frame base pointer from CSRs.
    assign frame_base_pointer = csr.afu_read_frame[QA_ADDR_SZ+QA_ADDR_OFFSET-1 : QA_ADDR_SZ+QA_ADDR_OFFSET-LOG_FRAME_BASE_POINTER];
    assign response_read_metadata = unpack_read_metadata(rx0.header);

    // Monitor frame data
    assign frame_header_valid = rx0.rdvalid && response_read_metadata.is_read && response_read_metadata.is_header;
    assign frame_ready_for_read = header_in_use(rx0.data);

    // Monitor grants for data reads.
    logic data_read_accepted;
    logic last_data_read_accepted;
    assign data_read_accepted = read_grant.reader_grant && (state == READ);
    assign last_data_read_accepted = data_read_accepted && (frame_chunks_total == frame_chunks);


    assign incoming_read_valid = rx0.rdvalid && response_read_metadata.is_read && !response_read_metadata.is_header;



    assign data_read_rdy = scoreboard_slot_rdy && state == READ;
    assign header_read_rdy = state == POLL_HEADER;

    assign frame_reader.read.request = data_read_rdy || header_read_rdy;
    assign frame_reader.read_header = read_header;

    // Read metadata
    assign data_read_metadata.is_read   = 1'b1;
    assign data_read_metadata.is_header = 1'b0;
    assign data_read_metadata.rob_addr  = scoreboard_slot_id;

    // Header metadata
    assign header_read_metadata.is_read   = 1'b1;
    assign header_read_metadata.is_header = 1'b1;
    assign header_read_metadata.rob_addr  = scoreboard_slot_id;

    logic release_frame;
    assign release_frame = frame_release_count_up && rx_enable;

    // Signals related to releasing read frames
    assign frame_reader.write_header  = frame_reader_release.write_header;
    assign frame_reader.write.request = frame_reader_release.write.request;
    assign frame_reader.data          = {read_line_last[CACHE_WIDTH-1:1], 1'b0};

    assign rx_data = read_line[UMF_WIDTH-1:0];


    // FSM state
    always_ff @(posedge clk) begin
        if (!resetb || !csr.afu_en) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end

    always_ff @(posedge clk) begin
        if (incoming_read_valid) begin
            read_line_last <= rx0.data;
        end
    end

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

    // Capture the number of chunks in a frame.  The chunk count arrives
    // with the header.  This code doesn't check that the header has actually
    // arrived this cycle.  Other logic will handle that.
    always_ff @(posedge clk) begin
        if (state == WAIT_HEADER)
        begin
            frame_chunks_total <= header_chunks(rx0.data);
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


    always@(negedge clk)
    begin
        if(QA_DRIVER_DEBUG)
        begin
            if(rx0.data != 0 && response_read_metadata.is_read)
            begin
                $display("Frame reader got a response: header %h data %h (low: %h)", rx0.header, rx0.data, rx0.data[LOG_FRAME_CHUNKS:0]);
                $display("Frame reader got a response: decode header ready %h chunks %h", frame_ready_for_read, header_chunks(rx0.data));
                $display("Frame reader got a response: is_read %h is_header %h", response_read_metadata.is_read, response_read_metadata.is_header);
            end
        end
    end



    always_comb begin
        read_header = 0;
        read_header.request_type = RdLine;
        read_header.address = {frame_base_pointer,frame_number,frame_chunks};
        read_header.mdata = (state == READ) ? pack_read_metadata(data_read_metadata) : pack_read_metadata(header_read_metadata);
    end


    qa_drv_scoreboard#(.N_ENTRIES(8),
                       .N_DATA_BITS($bits(t_QA_CACHE_LINE)),
                       .N_META_BITS(1))
        scoreboard(.clk,
                   .resetb,

                   .enq_en(data_read_accepted),
                   .enqMeta(last_data_read_accepted),
                   .notFull(scoreboard_slot_rdy),
                   .enqIdx(scoreboard_slot_id),

                   .enqData_en(incoming_read_valid),
                   .enqDataIdx(response_read_metadata.rob_addr[BUFFER_ADDR_WIDTH-1:0]),
                   .enqData(rx0.data),

                   .deq_en(rx_enable),
                   .notEmpty(scoreboard_not_empty),
                   .first(read_line),
                   .firstMeta(frame_release_count_up));

    frame_release
        releaseMod(.clk(clk),
                   .resetb(resetb),

                   .rdy(can_req_frame_release),

                   .csr(csr),
                   .frame_reader(frame_reader_release),
                   .write_grant(write_grant),

                   .frame_base_pointer(frame_base_pointer),
                   .release_frame(release_frame),

                   .dbg_frame_release);


    //
    // Debugging
    //

    // Low 32 bits of the most recent four read data responses
    logic [3:0][31:0] dbg_data_read_data;

    // The most recent four read data offsets from the region base
    logic [3:0][31:0] dbg_data_read_addr_offsets;

    // Number of data read requests and responses
    logic [31:0] dbg_n_data_read_rsp;
    logic [31:0] dbg_n_data_read_req;

    // A collection of flags
    logic [31:0] dbg_flags;
    assign dbg_flags[0] = scoreboard_slot_rdy;
    assign dbg_flags[1] = scoreboard_not_empty;
    assign dbg_flags[2] = can_req_frame_release;
    assign dbg_flags[3] = frame_reader_release.write.request;

    assign dbg_fifo_from_host = { dbg_data_read_data,
                                  dbg_data_read_addr_offsets,
                                  dbg_n_data_read_rsp,
                                  dbg_n_data_read_req,
                                  dbg_flags };

    always_ff @(posedge clk) begin
        if (!resetb) begin
            dbg_n_data_read_rsp <= 0;
            dbg_n_data_read_req <= 0;
            for (int i = 0; i < 4; i++) begin
                dbg_data_read_addr_offsets[i] <= 32'haaaaaaaa;
                dbg_data_read_data[i] <= 32'haaaaaaaa;
            end
        end
        else begin
            // Read data request accepted
            if (data_read_accepted)
            begin
                dbg_n_data_read_req <= dbg_n_data_read_req + 1;
                // Shift in request offset
                for (int i = 3; i > 0; i--)
                begin
                    dbg_data_read_addr_offsets[i] <= dbg_data_read_addr_offsets[i - 1];
                end
                dbg_data_read_addr_offsets[0] <= {frame_number, frame_chunks};
            end

            // Read data response
            if (incoming_read_valid)
            begin
                dbg_n_data_read_rsp <= dbg_n_data_read_rsp + 1;
                // Shift in response
                for (int i = 3; i > 0; i--)
                begin
                    dbg_data_read_data[i] <= dbg_data_read_data[i - 1];
                end
                dbg_data_read_data[0] <= rx0.data;
            end
        end
    end

endmodule
