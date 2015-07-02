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

module qa_drv_fifo_to_host
  #(UMF_WIDTH=128)
    (input logic clk,
     input logic resetb,

     input  t_RX_C0 rx0,

     input  t_CSR_AFU_STATE     csr,
     output t_FRAME_ARB         frame_writer,
     input  t_CHANNEL_GRANT_ARB write_grant,

     input  t_FROM_STATUS_MGR_FIFO_TO_HOST   status_to_fifo_to_host,
     output t_TO_STATUS_MGR_FIFO_TO_HOST     fifo_to_host_to_status,

     // LEAP-facing interface
     input [UMF_WIDTH-1:0]     tx_data,
     output logic              tx_rdy,
     input                     tx_enable
    );

    //=====================================================================
    //
    //   Data type describing a cache line as a vector of UMF_CHUNKs
    //
    //=====================================================================

    localparam N_UMF_CHUNKS_PER_CACHE_LINE = QA_CACHE_LINE_SZ / UMF_WIDTH;
    typedef logic [UMF_WIDTH-1 : 0] t_UMF_CHUNK;
    typedef logic [N_UMF_CHUNKS_PER_CACHE_LINE-1 : 0][UMF_WIDTH-1 : 0] t_CACHE_LINE_VEC_UMF_CHUNK;

    // Count of UMF_CHUNKs within a cache line
    typedef logic [$clog2(N_UMF_CHUNKS_PER_CACHE_LINE) : 0] t_UMF_CHUNK_CNT;


    //=====================================================================
    //
    //  Functions and simple logic
    //
    //=====================================================================

    //
    // Shift a new chunk into an existing line of data.
    //
    function automatic t_CACHE_LINE_VEC_UMF_CHUNK pushChunk;
        input t_CACHE_LINE_VEC_UMF_CHUNK line;
        input t_UMF_CHUNK chunk;
        begin
            for (int i = 0; i < N_UMF_CHUNKS_PER_CACHE_LINE - 1; i++)
            begin
                line[i] = line[i + 1];
            end
            line[N_UMF_CHUNKS_PER_CACHE_LINE-1] = chunk;

            pushChunk = line;
        end
    endfunction

    //
    // Last chunk in a line?
    //
    function automatic logic isLastChunk;
        input t_UMF_CHUNK_CNT cnt;
        begin
            // Number of chunks per line is a power of 2
            isLastChunk = cnt[$high(cnt)];
        end
    endfunction


    //=====================================================================
    //
    // Collect incoming chunks in a line-sized buffer.
    //
    //=====================================================================

    t_CACHE_LINE_VEC_UMF_CHUNK lineIn_data;

    // Number of chunks held in lineIn_data
    t_UMF_CHUNK_CNT lineIn_busy_chunks;

    // Number of real chunks in lineIn_data excluding flushes (see below)
    t_UMF_CHUNK_CNT lineIn_num_chunks;

    // Properties of the buffer
    logic lineIn_notFull;
    assign lineIn_notFull = ! isLastChunk(lineIn_busy_chunks);
    logic lineIn_notEmpty;
    assign lineIn_notEmpty = (lineIn_busy_chunks != t_UMF_CHUNK_CNT'(0));

    // Buffer has been drained by code below
    logic lineIn_deq;
    // The consumer may take either the entire buffer or leave one entry
    // in the most recent chunk.  The latter case hapens on the first line
    // in a message, where the first chunk is the message length.
    logic lineIn_deq_chunk_remainder;

    // The state machine can enforce a timeout on short messages sitting
    // here in the buffer by asserting lineIn_force_flush.  A flush request
    // rotates the partial line into proper position, thus sharing the
    // relatively expensive line shift hardware.
    logic lineIn_force_flush;

    //
    // Rotate new chunks into lineIn_data buffer.
    //
    assign tx_rdy = (lineIn_notFull || lineIn_deq) && ! lineIn_force_flush;
    
    always_ff @(posedge clk)
    begin
        if (tx_enable || (lineIn_force_flush && lineIn_notFull))
        begin
            lineIn_data <= pushChunk(lineIn_data, tx_data);
        end
    end

    //
    // Update chunk counter.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            lineIn_busy_chunks <= 0;
            lineIn_num_chunks  <= 0;
        end
        else if (lineIn_deq)
        begin
            // Buffer was consumed.  It now contains what was not consumed
            // (at most one chunk) plus possible new data.
            lineIn_busy_chunks <= t_UMF_CHUNK_CNT'(lineIn_deq_chunk_remainder) +
                                  t_UMF_CHUNK_CNT'(tx_enable);
            lineIn_num_chunks  <= t_UMF_CHUNK_CNT'(lineIn_deq_chunk_remainder) +
                                  t_UMF_CHUNK_CNT'(tx_enable);
        end
        else
        begin
            // A chunk becomes busy even on forced rotation, but the number of
            // real chunks increments only on tx_enable.
            lineIn_busy_chunks <= lineIn_busy_chunks +
                                  t_UMF_CHUNK_CNT'(tx_enable || lineIn_force_flush);
            lineIn_num_chunks  <= lineIn_num_chunks + t_UMF_CHUNK_CNT'(tx_enable);
        end
    end


    //=====================================================================
    //
    // Pointers that manage the ring buffer
    //
    //=====================================================================

    // Base address of the ring buffer
    t_CACHE_LINE_ADDR buffer_base_addr;
    assign buffer_base_addr = t_CACHE_LINE_ADDR'(csr.afu_write_frame);

    // Pointer to the oldest live entry in the ring buffer.  This pointer
    // determines whether the the buffer is full, waiting for the host to
    // consume the existing messages.  The pointer is updated by the host
    // as messages are consumed and updated in the FPGA by the status
    // manager.
    t_FIFO_TO_HOST_IDX oldest_write_line_idx;
    assign oldest_write_line_idx = status_to_fifo_to_host.oldest_write_line_idx;

    // Index of the line with the control word for the current group
    t_FIFO_TO_HOST_IDX cur_header_idx;

    // Index of the line currently collecting new data
    t_FIFO_TO_HOST_IDX cur_data_idx;

    assign fifo_to_host_to_status.next_write_line_idx = cur_header_idx;


    //=====================================================================
    //
    // Buffers holding pending writes
    //
    //=====================================================================

    t_CACHE_LINE_VEC_UMF_CHUNK cur_data_line;

    // A separate buffer is needed for the header since it must be written
    // last.  The first word in the header is a count of the number of
    // chunks in the message.
    t_CACHE_LINE_VEC_UMF_CHUNK cur_header_line;


    //=====================================================================
    //
    //  Main logic
    //
    //=====================================================================

    typedef enum logic [2:0]
    {
        STATE_WAIT_HEADER,
        STATE_WAIT_DATA,
        STATE_EMIT_DATA,
        STATE_EMIT_HEADER,
        STATE_EMIT_FENCE
    }
    t_STATE;

    t_STATE state;

    // Number of chunks in current message.  The counter is sized to
    // the total chunks the buffer can hold.
    logic [$clog2(N_UMF_CHUNKS_PER_CACHE_LINE) + $bits(t_FIFO_TO_HOST_IDX) - 1 : 0] num_chunks;

    //
    // Flush write buffer after a run of idle cycles or when the maximum
    // message size has been written.
    //
    logic [4:0] idle_cycles;
    logic flush_for_idle;
    logic flush_for_idle_hold;
    assign flush_for_idle = idle_cycles[$high(idle_cycles)] || flush_for_idle_hold;

    logic [10:0] active_lines;
    logic flush_full_message;
    logic flush_full_message_hold;
    assign flush_full_message = active_lines[$high(active_lines)] || flush_full_message_hold;

    //
    // Hold flush until message sent out
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            flush_for_idle_hold     <= 1'b0;
            flush_full_message_hold <= 1'b0;
        end
        else
        begin
            flush_for_idle_hold     <= flush_for_idle &&
                                       (state != STATE_EMIT_FENCE);

            flush_full_message_hold <= flush_full_message &&
                                       (state != STATE_EMIT_FENCE);
        end
    end

    //
    // Count idle cycles and message lengths in order to decide when to
    // complete a message.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            idle_cycles <= 0;
            active_lines <= 0;
        end
        else
        begin
            if (state == STATE_WAIT_HEADER)
            begin
                if (lineIn_notEmpty)
                begin
                    idle_cycles <= idle_cycles + 1;
                end
                else
                begin
                    // Message is completely empty
                    idle_cycles <= 0;
                end
            end
            else if ((state != STATE_WAIT_DATA) || lineIn_deq)
            begin
                // Not waiting for data or data just arrived
                idle_cycles <= 0;
            end
            else
            begin
                idle_cycles <= idle_cycles + 1;
            end

            // Active lines increments on successful data writes and resets
            // when a group is committed.
            if (state == STATE_EMIT_HEADER)
            begin
                active_lines <= 0;
            end
            else if ((state == STATE_EMIT_DATA) && write_grant.writer_grant)
            begin
                active_lines <= active_lines + 1;
            end
        end
    end

    // After some timeout for the incoming queue to produce what it has.
    assign lineIn_force_flush = (state == STATE_WAIT_HEADER) && flush_for_idle;

    // Consume incoming data based on state.
    assign lineIn_deq = (! lineIn_notFull && ! flush_full_message &&
                         ((state == STATE_WAIT_HEADER) || (state == STATE_WAIT_DATA)));

    // The header will never consume a full incoming line, since one chunk
    // is reserved for the message length.
    assign lineIn_deq_chunk_remainder = ((state == STATE_WAIT_HEADER) &&
                                         isLastChunk(lineIn_num_chunks));

    //
    // State transitions.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            state <= STATE_WAIT_HEADER;
            cur_header_idx <= 0;
            cur_data_idx <= 0;
        end
        else
        begin
            case (state)
              STATE_WAIT_HEADER:
                begin
                    // Wait for chunks to fill the available slots in the header
                    if (! lineIn_notFull)
                    begin
                        cur_header_line <= lineIn_data;

                        // Might be a partial line if flush_for_idle is set
                        if (isLastChunk(lineIn_num_chunks))
                        begin
                            // Left one chunk in the input buffer to make room
                            // for sending the message length.
                            num_chunks <= N_UMF_CHUNKS_PER_CACHE_LINE - 1;
                        end
                        else
                        begin
                            num_chunks <= lineIn_num_chunks;
                        end

                        state <= (flush_for_idle ? STATE_EMIT_HEADER :
                                                   STATE_WAIT_DATA);
                        cur_data_idx <= cur_data_idx + 1;
                    end
                end

              STATE_WAIT_DATA:
                begin
                    if (flush_full_message)
                    begin
                        state <= STATE_EMIT_HEADER;
                    end
                    else if (! lineIn_notFull)
                    begin
                        cur_data_line <= lineIn_data;
                        state <= STATE_EMIT_DATA;
                        num_chunks <= num_chunks + N_UMF_CHUNKS_PER_CACHE_LINE;
                    end
                    // Must test for idle last since lineIn_deq is allowed
                    // to fire in this state, allowing the existence of new
                    // data to take precedence over the timeout.
                    else if (flush_for_idle)
                    begin
                        state <= STATE_EMIT_HEADER;
                    end
                end

              STATE_EMIT_DATA:
                begin
                    if (write_grant.writer_grant)
                    begin
                        state <= (flush_full_message ? STATE_EMIT_HEADER :
                                                       STATE_WAIT_DATA);
                        cur_data_idx <= cur_data_idx + 1;
                    end
                end

              STATE_EMIT_HEADER:
                begin
                    if (write_grant.writer_grant)
                    begin
                        state <= STATE_EMIT_FENCE;
                    end
                end

              STATE_EMIT_FENCE:
                begin
                    if (write_grant.writer_grant)
                    begin
                        state <= STATE_WAIT_HEADER;

                        // Start position of next message
                        cur_header_idx <= cur_data_idx;
                    end
                end
            endcase
        end
    end


    // ====================================================================
    //
    //   Memory access logic.
    //
    // ====================================================================

    // No reads.
    assign frame_writer.read.request = 1'b0;

    // Write only allowed if space is available in the shared memory buffer
    logic allow_write;
    assign allow_write = (cur_data_idx + t_FIFO_TO_HOST_IDX'(1) != oldest_write_line_idx);

    assign frame_writer.write.request = allow_write &&
                                        ((state == STATE_EMIT_DATA) ||
                                         (state == STATE_EMIT_HEADER) ||
                                         (state == STATE_EMIT_FENCE));

    t_CACHE_LINE_VEC_UMF_CHUNK header_line;

    //
    // Set write address and data.
    //
    always_comb
    begin
        frame_writer.write_header = 0;
        frame_writer.write_header.mdata = 0;

        // First chunk in the header is the message length
        header_line = t_CACHE_LINE_VEC_UMF_CHUNK'({ cur_header_line,
                                                    t_UMF_CHUNK'(num_chunks) });

        case (state)
          STATE_EMIT_DATA:
            begin
                frame_writer.data = cur_data_line;
                frame_writer.write_header.request_type = WrThru;
                frame_writer.write_header.address = buffer_base_addr + cur_data_idx;
            end
          STATE_EMIT_HEADER:
            begin
                frame_writer.data = header_line;
                frame_writer.write_header.request_type = WrThru;
                frame_writer.write_header.address = buffer_base_addr + cur_header_idx;
            end
          default:
            begin
                frame_writer.data = header_line;
                frame_writer.write_header.request_type = WrFence;
                frame_writer.write_header.address = 0;
            end
        endcase
    end


    // ====================================================================
    //
    //   Debugging
    //
    // ====================================================================

`ifdef QA_DRIVER_DEBUG_Z

    // Debugger disabled
    assign fifo_to_host_to_status.dbg_fifo_state = t_AFU_DEBUG_RSP'(0);

`else

    t_UMF_CHUNK dbg_chunk_log[0 : 511];
    logic [8:0] dbg_chunk_next_idx;

    // Host requests a history register to read
    logic [8:0] dbg_chunk_read_idx;
    assign dbg_chunk_read_idx = dbg_chunk_next_idx -
                                9'(csr.afu_trigger_debug.subIdx);

    always_ff @(posedge clk)
    begin
        if (! resetb)
            dbg_chunk_next_idx <= 0;
        else if (tx_enable)
            dbg_chunk_next_idx <= dbg_chunk_next_idx + 1;
    end

    always_ff @(posedge clk)
    begin
        // Read a host-requested history register.
        fifo_to_host_to_status.dbg_fifo_state <= dbg_chunk_log[dbg_chunk_read_idx];

        // Log arriving UMF_CHUNKs
        if (tx_enable)
        begin
            dbg_chunk_log[dbg_chunk_next_idx] <= tx_data;
        end
    end

`endif // QA_DRIVER_DEBUG_Z

endmodule
