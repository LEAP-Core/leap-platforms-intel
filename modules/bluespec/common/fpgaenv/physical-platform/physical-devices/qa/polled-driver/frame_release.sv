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

module frame_release
    (input logic clk,
     input logic resetb,

     // Ready to release more frames?
     output logic rdy,

     input  t_CSR_AFU_STATE     csr,
     output frame_arb_t         frame_reader,
     input  channel_grant_arb_t write_grant,

     input [LOG_FRAME_BASE_POINTER - 1:0] frame_base_pointer,
     input release_frame,
     output t_AFU_DEBUG_RSP     dbg_frame_release
     );

    logic [LOG_FRAME_NUMBER - 1:0]   frame_number_clear; // Used to write back the header for clearing the frame.
    logic [LOG_FRAME_NUMBER - 1:0]   frame_number_clear_next;
    logic [LOG_FRAME_NUMBER - 1:0]   frames_to_be_cleared;
    logic [LOG_FRAME_NUMBER - 1:0]   frames_to_be_cleared_next;
    logic [LOG_FRAME_NUMBER - 1:0]   frame_number_zero;
    logic [LOG_FRAME_CHUNKS - 1:0]   frame_chunks_zero;

    tx_header_t write_header;

    assign frame_reader.write.request = ( frames_to_be_cleared > 0);
    assign frame_chunks_zero = LOG_FRAME_CHUNKS'(0);
    assign frame_number_zero = LOG_FRAME_NUMBER'(0);

    // Can't request more frame releases if the counter would wrap
    assign rdy = (frames_to_be_cleared != ~frame_number_zero);

    // FSM state
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            frame_number_clear <= 0;
        end
        else
        begin
            // If we get a grant, proceed to the next frame.
            frame_number_clear <= frame_number_clear + write_grant.reader_grant;
        end
    end

    always_comb
    begin
        frames_to_be_cleared_next = frames_to_be_cleared;
        if (release_frame)
            frames_to_be_cleared_next = frames_to_be_cleared_next + 1;
        if (write_grant.reader_grant)
            frames_to_be_cleared_next = frames_to_be_cleared_next - 1;
    end

    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            frames_to_be_cleared <= 0;
        end
        else
        begin
            frames_to_be_cleared <= frames_to_be_cleared_next;
        end
    end

    always_comb
    begin
        frame_reader.write_header = 0;
        frame_reader.write_header.request_type = WrThru;
        frame_reader.write_header.address = {frame_base_pointer, frame_number_clear, frame_chunks_zero};
        frame_reader.write_header.mdata = 0; // No metadata necessary
        frame_reader.data = 1'b0; // only need to set bottom bit.
    end


    //
    // Assertions
    //

    // Write granted without asking for a write?
    logic unexpected_write;

    logic unexpected_write_next;
    assign unexpected_write_next = write_grant.reader_grant &&
                                   ! frame_reader.write.request;

    always_ff @(posedge clk)
    begin
        if (! resetb)
            unexpected_write <= 0;
        else
            unexpected_write <= unexpected_write_next;

        assert (! unexpected_write_next) else
            $fatal("frame_release: Write granted without request!");
    end

    //
    // Debugging
    //

    // Last write grant
    logic [31:0] dbg_data_write_addr_offset;
    logic [15:0] dbg_num_frames_released;

    assign dbg_frame_release = { dbg_data_write_addr_offset,
                                 dbg_num_frames_released,
                                 15'b0,                 // Unused
                                 unexpected_write };

    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            dbg_data_write_addr_offset <= 0;
            dbg_num_frames_released <= 0;
        end
        else
        begin
            // Record address of most recent accepted write
            if (write_grant.reader_grant)
            begin
                dbg_data_write_addr_offset <= {frame_number_clear, frame_chunks_zero};
            end

            // Count the number of times a frame is released
            if (release_frame)
            begin
                dbg_num_frames_released <= dbg_num_frames_released + 1;
            end
        end
    end

endmodule
