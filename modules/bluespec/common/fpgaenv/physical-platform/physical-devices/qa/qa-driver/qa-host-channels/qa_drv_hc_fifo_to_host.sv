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

import cci_mpf_if_pkg::*;
import qa_drv_hc_types::*;
import qa_drv_hc_csr_types::*;


module qa_drv_hc_fifo_to_host
  #(
    // Which virtual channel should be used?
    parameter MEM_VIRTUAL_CHANNEL = 1
    )
   (
    input logic clk,
    input logic reset_n,

    input  t_if_cci_c0_Rx rx0,

    input  t_qa_drv_hc_csrs    csr,
    output t_frame_arb         frame_writer,
    input  t_channel_grant_arb write_grant,

    input  t_from_status_mgr_fifo_to_host   status_to_fifo_to_host,
    output t_to_status_mgr_fifo_to_host     fifo_to_host_to_status,

    // LEAP-facing interface
    input  t_cci_cldata tx_data,
    output logic        tx_rdy,
    input  logic        tx_enable
    );

    t_cci_cldata lineIn_data;
    logic lineIn_notEmpty;
    logic lineIn_deq;

    //
    // Buffer incoming messages in a FIFO.
    //
    cci_mpf_prim_fifo2
      #(
        .N_DATA_BITS(CCI_CLDATA_WIDTH)
        )
      inBuf
       (
        .clk,
        .reset_n,
        .enq_data(tx_data),
        .enq_en(tx_enable),
        .notFull(tx_rdy),
        .first(lineIn_data),
        .deq_en(lineIn_deq),
        .notEmpty(lineIn_notEmpty)
        );


    //=====================================================================
    //
    // Pointers that manage the ring buffer
    //
    //=====================================================================

    // Base address of the ring buffer
    t_cci_cl_paddr buffer_base_addr;
    assign buffer_base_addr = csr.hc_write_frame;

    // Pointer to the oldest live entry in the ring buffer.  This pointer
    // determines whether the the buffer is full, waiting for the host to
    // consume the existing messages.  The pointer is updated by the host
    // as messages are consumed and updated in the FPGA by the status
    // manager.
    t_fifo_to_host_idx oldest_write_idx;
    assign oldest_write_idx = status_to_fifo_to_host.oldestWriteIdx;

    // Index of the next ring buffer entry to write
    t_fifo_to_host_idx cur_data_idx;

    // Index of ring buffer before which data has been safely written and
    // protected by a memory fence.  This is the pointer passed to the host
    // to indicate the availability of new entries.  It tracks cur_data_idx
    // once pending writes have been committed, using a fence.
    t_fifo_to_host_idx written_data_idx;
    assign fifo_to_host_to_status.nextWriteIdx = written_data_idx;

    // Force a fence/flush after writing 25% of the buffer
    logic flush_for_writes;
    assign flush_for_writes = (cur_data_idx[$bits(t_fifo_to_host_idx)-2] !=
                               written_data_idx[$bits(t_fifo_to_host_idx)-2]);


    //=====================================================================
    //
    //  Main logic
    //
    //=====================================================================

    typedef enum logic [2:0]
    {
        STATE_WAIT_EMPTY,
        STATE_WAIT_DATA,
        STATE_EMIT_FENCE
    }
    t_STATE;

    t_STATE state;

    // Consume incoming data if it was written to the write buffer
    assign lineIn_deq = (write_grant.writerGrant && (state != STATE_EMIT_FENCE));

    //
    // Flush write buffer after a run of idle cycles.
    //
    logic [4:0] idle_cycles;
    logic flush_for_idle;
    logic flush_for_idle_hold;
    assign flush_for_idle = idle_cycles[$high(idle_cycles)] || flush_for_idle_hold;

    //
    // Hold flush until message sent out
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            flush_for_idle_hold <= 1'b0;
        end
        else
        begin
            flush_for_idle_hold <= flush_for_idle &&
                                   (state != STATE_EMIT_FENCE);
        end
    end

    //
    // Count idle cycles and message lengths in order to decide when to
    // complete a message.
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            idle_cycles <= 0;
        end
        else
        begin
            if ((state != STATE_WAIT_DATA) || lineIn_deq)
            begin
                // Not waiting for data or data just arrived
                idle_cycles <= 0;
            end
            else if (write_grant.canIssue)
            begin
                // Count idle cycles in order to decide when to flush.  Idle
                // cycles are counted only when the channel isn't busy since
                // the cost of a flush is high and we don't want to emit
                // extra flushes simply because channel writes have saturated
                // the memory bus.
                idle_cycles <= idle_cycles + 1;
            end
        end
    end


    //
    // State transitions.
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state <= STATE_WAIT_EMPTY;
            cur_data_idx <= 0;
            written_data_idx <= 0;
        end
        else
        begin
            case (state)
              STATE_WAIT_EMPTY:
                begin
                    // Was a new line written?
                    if (write_grant.writerGrant)
                    begin
                        state <= STATE_WAIT_DATA;
                        cur_data_idx <= cur_data_idx + t_fifo_to_host_idx'(1);
                    end
                end

              STATE_WAIT_DATA:
                begin
                    // New line written?
                    if (write_grant.writerGrant)
                    begin
                        cur_data_idx <= cur_data_idx + t_fifo_to_host_idx'(1);
                    end

                    // Time to make the writes visible to the host?
                    if (flush_for_idle || flush_for_writes)
                    begin
                        state <= STATE_EMIT_FENCE;
                    end
                end

              STATE_EMIT_FENCE:
                begin
                    if (write_grant.writerGrant)
                    begin
                        state <= STATE_WAIT_EMPTY;

                        // Update valid data pointer
                        written_data_idx <= cur_data_idx;
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
    assign allow_write = (cur_data_idx + t_fifo_to_host_idx'(1) != oldest_write_idx);

    assign frame_writer.write.request = csr.hc_en &&
                                        allow_write &&
                                        (lineIn_notEmpty ||
                                         (state == STATE_EMIT_FENCE));

    //
    // Set write address and data.
    //
    always_comb
    begin
        t_cci_mpf_ReqMemHdrParams write_params;
        write_params = cci_mpf_defaultReqHdrParams(0);
        write_params.vc_sel = t_ccip_vc'(MEM_VIRTUAL_CHANNEL);

        frame_writer.writeHeader = 0;
        frame_writer.writeHeader.mdata = 0;

        frame_writer.data = lineIn_data;

        case (state)
          STATE_EMIT_FENCE:
            begin
                frame_writer.writeHeader =
                    cci_genReqHdr(eREQ_WRFENCE,
                                  t_cci_cl_paddr'(0),
                                  t_cci_mdata'(0),
                                  write_params);
            end
          default:
            begin
                frame_writer.writeHeader =
                    cci_genReqHdr(eREQ_WRLINE_I,
                                  buffer_base_addr + cur_data_idx,
                                  t_cci_mdata'(0),
                                  write_params);
            end
        endcase
    end

endmodule
