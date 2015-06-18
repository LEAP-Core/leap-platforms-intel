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
  #(// Match N_SCOREBOARD_ENTRIES to the size of the scoreboard block RAM for
    // greatest efficiency.  Altera M20K memory is 512 x 32 bits. (32 is the
    // widest configuration.)
    N_SCOREBOARD_ENTRIES=512,
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

     output t_TO_STATUS_MGR_FIFO_FROM_HOST   fifo_from_host_to_status,
     input  t_FROM_STATUS_MGR_FIFO_FROM_HOST status_to_fifo_from_host
    );

    // Index of the next line to read in the ring buffer
    t_FIFO_FROM_HOST_IDX next_read_req_idx;

    // Index of the oldest line in the ring buffer not yet read.  This pointer
    // will be sent to the host every once in a while by qa_drv_status_manager
    // in order to regulate host writes to the ring buffer.
    t_FIFO_FROM_HOST_IDX oldest_read_line_idx;
    assign fifo_from_host_to_status.oldest_read_line_idx = oldest_read_line_idx;

    // The status manager updates the pointer to new data in the incoming
    // ring buffer and forwards it here.
    t_FIFO_FROM_HOST_IDX newest_read_line_idx;
    assign newest_read_line_idx = status_to_fifo_from_host.newest_read_line_idx;

    // Index of a scoreboard entry
    localparam N_SCOREBOARD_IDX_BITS = $clog2(N_SCOREBOARD_ENTRIES);
    typedef logic [N_SCOREBOARD_IDX_BITS-1 : 0] t_SCOREBOARD_IDX;

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
    read_metadata_t response_read_metadata;
    assign response_read_metadata = unpack_read_metadata(rx0.header);

    logic incoming_read_valid;
    assign incoming_read_valid = rx0.rdvalid &&
                                 response_read_metadata.is_read &&
                                 ! response_read_metadata.is_header;

    // FIFO stream to the host
    t_CACHE_LINE read_line;
    assign rx_data = read_line[UMF_WIDTH-1:0];

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
        else if (rx_enable)
        begin
            // Read respose.  Update the oldest pointer.
            oldest_read_line_idx <= oldest_read_line_idx + 1;

            assert (rx_rdy) else
                $fatal("qa_drv_fifo_from_host: rx_enable while no data valid!");
        end
    end


    qa_drv_scoreboard#(.N_ENTRIES(N_SCOREBOARD_ENTRIES),
                       .N_DATA_BITS($bits(t_CACHE_LINE)),
                       .N_META_BITS(0))
        scoreboard(.clk,
                   .resetb,

                   .enq_en(read_grant.reader_grant),
                   .enqMeta(2'b0),
                   .notFull(scoreboard_slot_rdy),
                   .enqIdx(scoreboard_slot_idx),

                   .enqData_en(incoming_read_valid),
                   .enqDataIdx(response_read_metadata.rob_addr[N_SCOREBOARD_IDX_BITS-1 : 0]),
                   .enqData(rx0.data),

                   .deq_en(rx_enable),
                   .notEmpty(rx_rdy),
                   .first(read_line),
                   .firstMeta());


    // ====================================================================
    //
    //   Manage memory requests
    //
    // ====================================================================

    // Base address of the ring buffer
    t_CACHE_LINE_ADDR buffer_base_addr;
    assign buffer_base_addr = t_CACHE_LINE_ADDR'(csr.afu_read_frame);

    tx_header_t read_header;
    read_metadata_t data_read_metadata;

    always_comb
    begin
        // No writes, ever
        frame_reader.write.request = 0;

        // Request a read when the incoming ring buffer has data and the
        // scoreboard has space.
        frame_reader.read.request = (next_read_req_idx != newest_read_line_idx) &&
                                    scoreboard_slot_rdy;

        read_header = 0;
        read_header.request_type = RdLine;

        // Read metadata
        data_read_metadata.is_read   = 1'b1;
        data_read_metadata.is_header = 1'b0;
        data_read_metadata.rob_addr  = scoreboard_slot_idx;
        read_header.mdata = pack_read_metadata(data_read_metadata);

        // By adding to form the address instead of replacing low bits we avoid
        // the requirement that the buffer be aligned to the buffer size.
        // The buffer size must still be a power of two because we depend on
        // pointers wrapping from the last to the first entry.
        read_header.address = buffer_base_addr + next_read_req_idx;

        frame_reader.read_header = read_header;
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
        else if (read_grant.reader_grant)
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
    assign dbg_flags[1] = rx_rdy;

    assign fifo_from_host_to_status.dbg_fifo_state =
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
            if (read_grant.reader_grant)
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

endmodule
