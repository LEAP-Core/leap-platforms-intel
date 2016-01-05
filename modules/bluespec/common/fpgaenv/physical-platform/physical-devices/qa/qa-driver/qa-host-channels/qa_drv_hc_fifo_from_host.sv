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

import qa_drv_hc_types::*;

module qa_drv_hc_fifo_from_host
  #(
    parameter N_SCOREBOARD_ENTRIES=256
    )
   (
    input logic clk,
    input logic reset_n,

    input  t_if_cci_c0_Rx rx0,

    input  t_csr_afu_state     csr,
    output t_frame_arb         frame_reader,
    input  t_channel_grant_arb read_grant,

    output t_cci_cldata rx_data,
    output logic        rx_rdy,
    input  logic        rx_enable,

    output t_to_status_mgr_fifo_from_host   fifo_from_host_to_status,
    input  t_from_status_mgr_fifo_from_host status_to_fifo_from_host
    );

    t_cci_cldata outQ_enq_data;
    logic outQ_enq_en;
    logic outQ_notFull;

    //
    // Buffer the outgoing stream to control timing.
    //
    cci_mpf_prim_fifo2
      #(
        .N_DATA_BITS(CCI_CLDATA_WIDTH)
        )
      outQ
        (
         .clk,
         .reset_n,
         .enq_data(outQ_enq_data),
         .enq_en(outQ_enq_en),
         .notFull(outQ_notFull),
         .first(rx_data),
         .deq_en(rx_enable),
         .notEmpty(rx_rdy)
         );


    //=====================================================================
    //
    // Pointers that manage the ring buffer
    //
    //=====================================================================

    // Index of the next line to read in the ring buffer
    t_fifo_from_host_idx next_read_req_idx;

    // Index of the oldest line in the ring buffer not yet read.  This pointer
    // will be sent to the host every once in a while by qa_drv_status_manager
    // in order to regulate host writes to the ring buffer.
    t_fifo_from_host_idx oldest_read_line_idx;
    assign fifo_from_host_to_status.oldestReadLineIdx = oldest_read_line_idx;

    // The status manager updates the pointer to new data in the incoming
    // ring buffer and forwards it here.
    t_fifo_from_host_idx newest_read_line_idx;
    assign newest_read_line_idx = status_to_fifo_from_host.newestReadLineIdx;

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

    // Pass data from scoreboard toward the FPGA-side client when a message
    // is available and space is available in outQ.
    logic sc_notEmpty;
    assign outQ_enq_en = sc_notEmpty && outQ_notFull;

    // Is the incoming read a FIFO read response?
    t_read_metadata response_read_metadata;
    assign response_read_metadata = unpack_read_metadata(rx0.hdr);

    logic incoming_read_valid;
    assign incoming_read_valid = rx0.rdValid &&
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
        if (!reset_n)
        begin
            oldest_read_line_idx <= 0;
        end
        else if (outQ_enq_en)
        begin
            // Read respose.  Update the oldest pointer.
            oldest_read_line_idx <= oldest_read_line_idx + 1;
        end
    end


    cci_mpf_prim_scoreboard
      #(
        .N_ENTRIES(N_SCOREBOARD_ENTRIES),
        .N_DATA_BITS(CCI_CLDATA_WIDTH),
        .N_META_BITS(0)
        )
      scoreboard
        (
         .clk,
         .reset_n,

         .enq_en(read_grant.readerGrant),
         .enqMeta(2'b0),
         .notFull(scoreboard_slot_rdy),
         .enqIdx(scoreboard_slot_idx),

         .enqData_en(incoming_read_valid),
         .enqDataIdx(t_SCOREBOARD_IDX'(response_read_metadata.robAddr)),
         .enqData(rx0.data),

         .deq_en(outQ_enq_en),
         .notEmpty(sc_notEmpty),
         .first(outQ_enq_data),
         .firstMeta()
         );


    // ====================================================================
    //
    //   Manage memory requests
    //
    // ====================================================================

    // Base address of the ring buffer
    t_cci_cl_paddr buffer_base_addr;
    assign buffer_base_addr = t_cci_cl_paddr'(csr.afu_read_frame);

    t_read_metadata data_read_metadata;
    t_cci_mpf_ReqMemHdrParams read_params;

    always_comb
    begin
        // No writes, ever
        frame_reader.write.request = 0;

        // Request a read when the incoming ring buffer has data and the
        // scoreboard has space.
        frame_reader.read.request = (next_read_req_idx != newest_read_line_idx) &&
                                    scoreboard_slot_rdy;

        read_params = cci_mpf_defaultReqHdrParams();
        read_params.addrIsVirtual = 1'b0;

        // Read metadata
        data_read_metadata.reserved = 1'b0;
        data_read_metadata.isRead   = 1'b1;
        data_read_metadata.isHeader = 1'b0;
        data_read_metadata.robAddr  = scoreboard_slot_idx;

        // By adding to form the address instead of replacing low bits we avoid
        // the requirement that the buffer be aligned to the buffer size.
        // The buffer size must still be a power of two because we depend on
        // pointers wrapping from the last to the first entry.
        frame_reader.readHeader =
            cci_genReqHdr(eREQ_RDLINE_I,
                          buffer_base_addr + next_read_req_idx,
                          pack_read_metadata(data_read_metadata),
                          read_params);
    end


    //
    // Track the pointer for the next read request.
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
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

endmodule
