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
  #(
    N_SCOREBOARD_ENTRIES=256,
    UMF_WIDTH=128
    )
   (
    input logic clk,
    input logic resetb,

    input t_RX_C0 rx0,

    input  t_CSR_AFU_STATE     csr,
    output t_FRAME_ARB         frame_reader,
    input  t_CHANNEL_GRANT_ARB read_grant,

    output [UMF_WIDTH-1:0]     rx_data,
    output                     rx_rdy,
    input                      rx_enable,

    output t_TO_STATUS_MGR_FIFO_FROM_HOST   fifo_from_host_to_status,
    input  t_FROM_STATUS_MGR_FIFO_FROM_HOST status_to_fifo_from_host
    );

    typedef logic [UMF_WIDTH-1:0] t_UMF_CHUNK;

    // Index of the next line to read in the ring buffer
    t_FIFO_FROM_HOST_IDX next_read_req_idx;

    // Index of the oldest line in the ring buffer not yet read.  This pointer
    // will be sent to the host every once in a while by qa_drv_status_manager
    // in order to regulate host writes to the ring buffer.
    t_FIFO_FROM_HOST_IDX oldest_read_line_idx;
    assign fifo_from_host_to_status.oldestReadLineIdx = oldest_read_line_idx;

    // The status manager updates the pointer to new data in the incoming
    // ring buffer and forwards it here.
    t_FIFO_FROM_HOST_IDX newest_read_line_idx;
    assign newest_read_line_idx = status_to_fifo_from_host.newestReadLineIdx;

    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_SCOREBOARD_IDX;

    // ====================================================================
    //
    //   Buffer the outgoing stream to control timing.
    //
    // ====================================================================

    t_UMF_CHUNK outQ_enq_data;
    logic outQ_enq_en;
    logic outQ_notFull;

    qa_drv_prim_fifo2#(.N_DATA_BITS($bits(t_UMF_CHUNK)))
        outQ(.clk, .resetb,
             .enq_data(outQ_enq_data),
             .enq_en(outQ_enq_en),
             .notFull(outQ_notFull),
             .first(rx_data),
             .deq_en(rx_enable),
             .notEmpty(rx_rdy));


    // ====================================================================
    //
    //   Convert a stream of cache lines into a stream of UMF_CHUNKs.
    //
    // ====================================================================

    typedef enum
    {
        STATE_NEW_MESSAGE,
        STATE_READ_HEADER,
        STATE_NEW_LINE,
        STATE_VALID_CHUNK
    }
    t_STATE;

    t_STATE state;

    localparam UMF_CHUNKS_PER_LINE = QA_CACHE_LINE_SZ / UMF_WIDTH;

    // Cache line as a vector of UMF_CHUNKs
    typedef t_UMF_CHUNK [UMF_CHUNKS_PER_LINE-1 : 0] t_CACHE_LINE_UMF_CHUNK_VEC;

    // Index of a UMF_CHUNK within a line
    typedef logic [$clog2(UMF_CHUNKS_PER_LINE)-1 : 0] t_UMF_CHUNK_IDX;

    // Count of UMF_CHUNKs in a message group.  The size of this counter
    // limits the maximum message size.
    typedef logic [15:0] t_NUM_UMF_CHUNKS;

    // Number of chunks remaining in the current message
    t_NUM_UMF_CHUNKS num_chunks;

    // Index of the chunk within the current line
    t_UMF_CHUNK_IDX chunk_in_line;

    logic is_last_chunk_in_line;
    assign is_last_chunk_in_line = (chunk_in_line == t_UMF_CHUNK_IDX'(UMF_CHUNKS_PER_LINE-1));

    // Cache line currently being processed
    t_CACHE_LINE_UMF_CHUNK_VEC cur_line;

    // Commands and wires to the scoreboard
    logic sc_not_empty;
    t_CACHE_LINE_UMF_CHUNK_VEC sc_next_line;

    // Continue to next line if the current chunk is ending and valid data
    // exists in the scoreboard.
    logic continue_to_next_line;
    assign continue_to_next_line =
        ((state == STATE_VALID_CHUNK) &&
         outQ_enq_en &&
         is_last_chunk_in_line &&
         (num_chunks != t_NUM_UMF_CHUNKS'(1)));

    // Is the current line completely drained?
    logic need_next_line;
    assign need_next_line = ((state == STATE_NEW_MESSAGE) ||
                             (state == STATE_NEW_LINE) ||
                             continue_to_next_line);

    // Time to request a new line from the scoreboard?
    logic sc_req_next_line;
    assign sc_req_next_line = sc_not_empty && need_next_line;

    // Data is ready when it is sitting in the outbound buffer
    assign outQ_enq_en = (state == STATE_VALID_CHUNK) && outQ_notFull;
    assign outQ_enq_data = cur_line[0];

    //
    // State machine.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            state <= STATE_NEW_MESSAGE;
        end
        else
        begin
            case (state)
              STATE_NEW_MESSAGE:
                begin
                    if (sc_not_empty)
                    begin
                        state <= STATE_READ_HEADER;
                    end
                end

              STATE_READ_HEADER:
                begin
                    // The number of chunks is the first entry in the message
                    num_chunks <= t_NUM_UMF_CHUNKS'(cur_line[0]);
                    chunk_in_line <= 1;

                    state <= STATE_VALID_CHUNK;
                end

              STATE_NEW_LINE:
                begin
                    chunk_in_line <= 0;

                    if (sc_not_empty)
                    begin
                        state <= STATE_VALID_CHUNK;
                    end
                end

              STATE_VALID_CHUNK:
                begin
                    // If the client consumed a chunk then advance the poniters
                    if (outQ_enq_en)
                    begin
                        if (num_chunks == t_NUM_UMF_CHUNKS'(1))
                        begin
                            // End of message
                            state <= STATE_NEW_MESSAGE;
                        end
                        else if (is_last_chunk_in_line)
                        begin
                            // End of line.  If the scoreboard has another line
                            // just keep going.  Otherwise, wait for the next
                            // line.
                            if (! sc_not_empty)
                            begin
                                state <= STATE_NEW_LINE;
                            end
                        end

                        num_chunks <= num_chunks - t_NUM_UMF_CHUNKS'(1);
                        chunk_in_line <= chunk_in_line + t_UMF_CHUNK_IDX'(1);
                    end
                end
            endcase
        end
    end


    //
    // Manage cur_line.
    //
    always_ff @(posedge clk)
    begin
        if (need_next_line)
        begin
            cur_line <= sc_next_line;
        end

        // Rotate if reading the header or sending a chunk to the client.
        else if ((state == STATE_READ_HEADER) ||
                 (outQ_enq_en && (state == STATE_VALID_CHUNK)))
        begin
            for (int i = 0; i < UMF_CHUNKS_PER_LINE-1; i++)
            begin
                cur_line[i] <= cur_line[i + 1];
            end
        end
    end


    // ====================================================================
    //
    //   Reads are not returned in order.  The scoreboard sorts read
    //   responses.
    //
    // ====================================================================

    t_SCOREBOARD_IDX scoreboard_slot_idx;
    logic            scoreboard_slot_rdy;
    logic            scoreboard_slot_en;

    // Is the incoming read a FIFO read response?
    t_READ_METADATA response_read_metadata;
    assign response_read_metadata = unpack_read_metadata(rx0.header);

    logic incoming_read_valid;
    assign incoming_read_valid = rx0.rdvalid &&
                                 response_read_metadata.isRead &&
                                 ! response_read_metadata.isHeader;


    //
    // Track the oldest read line.  This pointer will be forwarded to the
    // host by the status manager.  It tells the host when a buffer slot
    // has been consumed and may be overwritten.
    //
    // The pointer is updated as responses exit the scoreboard.  This is
    // much simpler than tracking out of order responses as they enter
    // the scoreboard.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            oldest_read_line_idx <= 0;
        end
        else if (sc_req_next_line)
        begin
            // Read respose.  Update the oldest pointer.
            oldest_read_line_idx <= oldest_read_line_idx + 1;
        end
    end


    qa_drv_prim_scoreboard#(.N_ENTRIES(N_SCOREBOARD_ENTRIES),
                            .N_DATA_BITS($bits(t_CACHE_LINE)),
                            .N_META_BITS(0))
        scoreboard(.clk,
                   .resetb,

                   .enq_en(read_grant.readerGrant),
                   .enqMeta(2'b0),
                   .notFull(scoreboard_slot_rdy),
                   .enqIdx(scoreboard_slot_idx),

                   .enqData_en(incoming_read_valid),
                   .enqDataIdx(response_read_metadata.robAddr[N_SCOREBOARD_IDX_BITS-1 : 0]),
                   .enqData(rx0.data),

                   .deq_en(sc_req_next_line),
                   .notEmpty(sc_not_empty),
                   .first(sc_next_line),
                   .firstMeta());


    // ====================================================================
    //
    //   Manage memory requests
    //
    // ====================================================================

    // Base address of the ring buffer
    t_CACHE_LINE_ADDR buffer_base_addr;
    assign buffer_base_addr = t_CACHE_LINE_ADDR'(csr.afu_read_frame);

    t_TX_HEADER read_header;
    t_READ_METADATA data_read_metadata;

    always_comb
    begin
        // No writes, ever
        frame_reader.write.request = 0;

        // Request a read when the incoming ring buffer has data and the
        // scoreboard has space.
        frame_reader.read.request = (next_read_req_idx != newest_read_line_idx) &&
                                    scoreboard_slot_rdy;

        read_header = 0;
        read_header.requestType = RdLine_I;

        // Read metadata
        data_read_metadata.reserved = 1'b0;
        data_read_metadata.isRead   = 1'b1;
        data_read_metadata.isHeader = 1'b0;
        data_read_metadata.robAddr  = scoreboard_slot_idx;
        read_header.mdata = pack_read_metadata(data_read_metadata);

        // By adding to form the address instead of replacing low bits we avoid
        // the requirement that the buffer be aligned to the buffer size.
        // The buffer size must still be a power of two because we depend on
        // pointers wrapping from the last to the first entry.
        read_header.address = buffer_base_addr + next_read_req_idx;

        frame_reader.readHeader = read_header;
    end


    //
    // Track the pointer for the next read request.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            next_read_req_idx <= 0;
        end
        else if (read_grant.readerGrant)
        begin
            // Read request successful.  Move to next line.
            next_read_req_idx <= next_read_req_idx + 1;

            assert (frame_reader.read.request) else
                $fatal("qa_drv_fifo_from_host: read grant without request!");
        end
    end


    // ====================================================================
    //
    //   Debugging
    //
    // ====================================================================

`ifdef QA_DRIVER_DEBUG_Z

    // Debugger disabled
    assign fifo_from_host_to_status.dbgFIFOState = t_AFU_DEBUG_RSP'(0);

`else

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
    assign dbg_flags[1] = (state == STATE_VALID_CHUNK);

    assign fifo_from_host_to_status.dbgFIFOState =
        { dbg_data_read_data,
          dbg_data_read_addr_offsets,
          dbg_n_data_read_rsp,
          dbg_n_data_read_req,
          dbg_flags };

    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            dbg_n_data_read_rsp <= 0;
            dbg_n_data_read_req <= 0;
            for (int i = 0; i < 4; i++)
            begin
                dbg_data_read_addr_offsets[i] <= 32'haaaaaaaa;
                dbg_data_read_data[i] <= 32'haaaaaaaa;
            end
        end
        else
        begin
            // Read data request accepted
            if (read_grant.readerGrant)
            begin
                dbg_n_data_read_req <= dbg_n_data_read_req + 1;
                // Shift in request offset
                for (int i = 3; i > 0; i--)
                begin
                    dbg_data_read_addr_offsets[i] <= dbg_data_read_addr_offsets[i - 1];
                end
                dbg_data_read_addr_offsets[0] <= next_read_req_idx;
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

`endif // QA_DRIVER_DEBUG_Z

endmodule
