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
  #(parameter BUFFER_DEPTH=64,
    BUFFER_ADDR_WIDTH=6,
    CACHE_WIDTH=512,
    UMF_WIDTH=128)
    (input logic clk,
     input logic resetb,

     input rx_c0_t rx0,

     input  t_CSR_AFU_STATE     csr,
     output frame_arb_t         frame_writer,
     input  channel_grant_arb_t write_grant,
     input  channel_grant_arb_t read_grant,

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

    localparam N_UMF_CHUNKS_PER_CACHE_LINE = CACHE_WIDTH / UMF_WIDTH;
    typedef logic [UMF_WIDTH-1 : 0] t_UMF_CHUNK;
    typedef logic [N_UMF_CHUNKS_PER_CACHE_LINE-1 : 0][UMF_WIDTH-1 : 0] t_CACHE_LINE_VEC_UMF_CHUNK;

    // Index of a UMF_CHUNK within a cache line
    typedef logic [$clog2(N_UMF_CHUNKS_PER_CACHE_LINE)-1 : 0] t_UMF_CHUNK_IDX;


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
    t_FIFO_TO_HOST_IDX cur_data_idx_next;

    // Index of the UMF_CHUNK within the current line
    t_UMF_CHUNK_IDX cur_chunk_idx;
    t_UMF_CHUNK_IDX cur_chunk_idx_next;

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
    //  Functions and simple logic
    //
    //=====================================================================

    //
    // Shift a new chunk into an existing line of data.
    //
    function automatic t_CACHE_LINE_VEC_UMF_CHUNK push_chunk;
        input t_CACHE_LINE_VEC_UMF_CHUNK line;
        input t_UMF_CHUNK chunk;
        begin
            for (int i = 0; i < N_UMF_CHUNKS_PER_CACHE_LINE - 1; i++)
            begin
                line[i] = line[i + 1];
            end
            line[N_UMF_CHUNKS_PER_CACHE_LINE-1] = chunk;

            push_chunk = line;
        end
    endfunction

    //
    // Last chunk in a line?
    //
    function automatic logic is_last_chunk;
        input t_UMF_CHUNK_IDX idx;
        begin
            is_last_chunk =
                (idx == t_UMF_CHUNK_IDX'(N_UMF_CHUNKS_PER_CACHE_LINE-1));
        end
    endfunction


    logic header_line_active;
    assign header_line_active = (cur_header_idx == cur_data_idx);


    //=====================================================================
    //
    //  Main logic
    //
    //=====================================================================

    typedef enum logic [2:0]
    {
        STATE_NORMAL,
        STATE_ROTATE,
        STATE_EMIT_DATA,
        STATE_EMIT_HEADER,
        STATE_EMIT_FENCE
    }
    t_STATE;

    t_STATE state;
    t_STATE state_next;

    logic [4:0] idle_cycles;
    logic [4:0] idle_cycles_next;

    logic [10:0] active_lines;
    logic [10:0] active_lines_next;

    logic force_buffer_flush;
    logic force_buffer_flush_next;

    // Number of chunks in current message.  The counter is sized to
    // the total chunks the buffer can hold.
    logic [$clog2(N_UMF_CHUNKS_PER_CACHE_LINE) + $bits(t_FIFO_TO_HOST_IDX) - 1 : 0] num_chunks;

    // Are new messages allowed?  This will go low if the write path
    // is blocked either because no credit is available or because the
    // write pipeline is busy.
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            tx_rdy <= 0;
        end
        else
        begin
            tx_rdy <= (state_next == STATE_NORMAL) &&
                      ! force_buffer_flush_next &&
                      (cur_data_idx_next + t_FIFO_TO_HOST_IDX'(1) != oldest_write_line_idx);
        end
    end

    //
    // Flush write buffer after a run of idle cycles or when 1K lines have
    // been written.
    //
    // The primary product of this logic is "force_buffer_flush".
    //
    always_comb
    begin
        // Idle cycles resets on activity and increments on inactivity
        if (state == STATE_NORMAL)
        begin
            idle_cycles_next = (tx_enable ? 0 : idle_cycles + 5'd1);
        end
        else
        begin
            idle_cycles_next = 0;
        end

        // Active lines increments on successful data writes and resets
        // when a group is committed.
        if (state == STATE_EMIT_HEADER)
        begin
            active_lines_next = 0;
        end
        else if ((state == STATE_EMIT_DATA) && write_grant.writer_grant)
        begin
            active_lines_next = active_lines + 1;
        end
        else
        begin
            active_lines_next = active_lines;
        end

        if (state == STATE_EMIT_HEADER)
        begin
            force_buffer_flush_next = 0;
        end
        else if (! header_line_active || (cur_chunk_idx != 1))
        begin
            // Some data has been written to the local buffer.  (Either
            // the header is full or at least one chunk has been written
            // to the header.)
            //
            // Is the cycle counter or the number of active lines too high?
            force_buffer_flush_next = force_buffer_flush ||
                                      idle_cycles_next[$high(idle_cycles)] ||
                                      active_lines_next[$high(active_lines)];
        end
        else
        begin
            force_buffer_flush_next = force_buffer_flush;
        end
    end

    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            force_buffer_flush <= 0;
            idle_cycles <= 0;
            active_lines <= 0;
        end
        else
        begin
            force_buffer_flush <= force_buffer_flush_next;
            idle_cycles <= idle_cycles_next;
            active_lines <= active_lines_next;
        end
    end


    //
    // State transitions.
    //
    always_comb
    begin
        state_next = state;

        case (state)
          STATE_NORMAL:
            begin
                if (! header_line_active && tx_enable && is_last_chunk(cur_chunk_idx))
                begin
                    // Data line is full.  Write to memory.
                    state_next = STATE_EMIT_DATA;
                end
                else if (force_buffer_flush)
                begin
                    // Time to close the current buffer
                    if (cur_chunk_idx == t_UMF_CHUNK_IDX'(0))
                    begin
                        // Most recent data line is empty.  Ready to emit
                        // header.
                        state_next = STATE_EMIT_HEADER;
                    end
                    else
                    begin
                        // Need to rotate the most recent data line into
                        // position.
                        state_next = STATE_ROTATE;
                    end
                end

                assert(!(tx_enable && force_buffer_flush)) else
                    $fatal("qa_drv_fifo_to_host: tx_enable same cycle as force_buffer_flush!");
            end

          STATE_ROTATE:
            begin
                if (is_last_chunk(cur_chunk_idx))
                begin
                    // Done rotating
                    if (header_line_active)
                    begin
                        // Short message -- just the header line
                        state_next = STATE_EMIT_HEADER;
                    end
                    else
                    begin
                        // Emit the last data line and then the header
                        state_next = STATE_EMIT_DATA;
                    end
                end
            end

          STATE_EMIT_DATA:
            begin
                if (write_grant.writer_grant)
                begin
                    state_next = (force_buffer_flush ? STATE_EMIT_HEADER :
                                                       STATE_NORMAL);
                end
            end

          STATE_EMIT_HEADER:
            begin
                if (write_grant.writer_grant)
                begin
                    state_next = STATE_EMIT_FENCE;
                end
            end


          STATE_EMIT_FENCE:
            begin
                if (write_grant.writer_grant)
                begin
                    state_next = STATE_NORMAL;
                end
            end

        endcase
    end

    always_ff @(posedge clk)
    begin
        if (!resetb)
            state <= STATE_NORMAL;
        else
            state <= state_next;
    end


    //
    // Track the pointer to the header line.  It moves only as the header
    // is being emitted.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            cur_header_idx <= 0;
        end
        else if ((state == STATE_EMIT_FENCE) && write_grant.writer_grant)
        begin
            cur_header_idx <= cur_data_idx;
        end
    end


    //
    // Count chunks in a message.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            num_chunks <= 0;
        end
        else if (tx_enable)
        begin
            num_chunks <= num_chunks + 1;
        end
        else if (state == STATE_EMIT_FENCE)
        begin
            num_chunks <= 0;
        end
    end


    //
    // Consume new messages and update local buffers.
    //
    always_ff @(posedge clk)
    begin
        if (tx_enable || (state == STATE_ROTATE))
        begin
            // Push tx_data even for the STATE_ROTATE case to simplify the
            // hardware.  The location will be ignored by the host.
            cur_data_line <= push_chunk(cur_data_line, tx_data);

            if (is_last_chunk(cur_chunk_idx) && header_line_active)
            begin
                // Store the header line in a separate buffer.  It must
                // be emitted last since it holds a count of the number
                // of chunks in the message.
                cur_header_line <= push_chunk(cur_data_line, tx_data);
            end
        end
    end

    always_comb
    begin
        cur_chunk_idx_next = cur_chunk_idx;
        cur_data_idx_next = cur_data_idx;

        if (tx_enable || (state == STATE_ROTATE))
        begin
            // Update pointers
            if (! is_last_chunk(cur_chunk_idx))
            begin
                // Current line still has space
                cur_chunk_idx_next = cur_chunk_idx + 1;
            end
            else
            begin
                // End of current line
                if (header_line_active)
                begin
                    // Move on to the next line
                    cur_data_idx_next = cur_data_idx + 1;
                end

                // Update pointers
                cur_chunk_idx_next = 0;
            end
        end
        else if ((state == STATE_EMIT_DATA) && write_grant.writer_grant)
        begin
            cur_data_idx_next = cur_data_idx + 1;
        end
        else if (state == STATE_EMIT_HEADER)
        begin
            // Prepare for next message.  Leave an open position for the
            // chunk count in the next message header.
            cur_chunk_idx_next = 1;
        end
    end

    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            // cur_chunk_idx set to 1 in headers because the first slot will
            // hold a count of chunks.
            cur_chunk_idx <= 1;
            cur_data_idx <= 0;
        end
        else
        begin
            cur_chunk_idx <= cur_chunk_idx_next;
            cur_data_idx <= cur_data_idx_next;
        end
    end


    // ====================================================================
    //
    //   Memory access logic.
    //
    // ====================================================================

    // No reads.
    assign frame_writer.read.request = 1'b0;

    assign frame_writer.write.request = (state == STATE_EMIT_DATA) ||
                                        (state == STATE_EMIT_HEADER) ||
                                        (state == STATE_EMIT_FENCE);

    t_CACHE_LINE_VEC_UMF_CHUNK header_line;

    //
    // Set write address and data.
    //
    always_comb
    begin
        frame_writer.write_header = 0;
        frame_writer.write_header.mdata = 0;

        header_line = cur_header_line;
        header_line[0] = t_UMF_CHUNK'(num_chunks);

        case (state)
          STATE_EMIT_DATA:
            begin
                frame_writer.data = cur_data_line;
                frame_writer.write_header.request_type = WrLine;
                frame_writer.write_header.address = buffer_base_addr + cur_data_idx;
            end
          STATE_EMIT_HEADER:
            begin
                frame_writer.data = header_line;
                frame_writer.write_header.request_type = WrLine;
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
endmodule
