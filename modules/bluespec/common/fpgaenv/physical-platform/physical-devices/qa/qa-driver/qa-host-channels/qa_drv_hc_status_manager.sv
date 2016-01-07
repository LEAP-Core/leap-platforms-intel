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

import qa_drv_hc_types::*;
import qa_drv_hc_csr_types::*;


module qa_drv_hc_status_manager
    (input logic clk,
     input logic reset_n,

     input  t_if_cci_c0_Rx rx0,

     input  t_qa_drv_hc_csrs     csr,
     output t_frame_arb          status_mgr_req,
     input  t_channel_grant_arb  read_grant,
     input  t_channel_grant_arb  write_grant,

     input  t_to_status_mgr_fifo_from_host   fifo_from_host_to_status,
     output t_from_status_mgr_fifo_from_host status_to_fifo_from_host,

     input  t_to_status_mgr_fifo_to_host     fifo_to_host_to_status,
     output t_from_status_mgr_fifo_to_host   status_to_fifo_to_host,

     input  t_to_status_mgr_tester           tester_to_status
    );

    //
    // Offsets in CTRL used for communicating state with the host.
    //
    // THESE OFFSETS MUST MATCH THE HOST!
    //
    localparam CTRL_OFFSET_CFG        = 0;
    localparam CTRL_OFFSET_FIFO_STATE = 1;
    localparam CTRL_OFFSET_POLL_STATE = 2;

    
    //
    // CTRL buffer addressing.
    //
    function automatic [31:0] ctrl_line_offset_to_addr(
        input int offset_l
        );

        begin
            // The frame base is at least 4KB aligned.  We can use |
            // instead of +.
            ctrl_line_offset_to_addr = csr.hc_ctrl_frame | 4'(offset_l);
        end
    endfunction


    //=================================================================
    // Status READER FSM
    //=================================================================

    //
    // Status reader loop exists to track two FIFO pointers coming
    // from the host:
    //   1.  FIFO from host to FPGA:  newest_read_line_idx is the index of
    //       the last entry available on the ring buffer.
    //   2.  FIFO from FPGA to host:  index of the oldest entry read by
    //       the host.  This manages credit to send more to the host without
    //       overwriting unread messages.
    //
    t_fifo_from_host_idx newest_read_line_idx;
    assign status_to_fifo_from_host.newestReadLineIdx = newest_read_line_idx;

    t_fifo_to_host_idx oldest_write_idx;
    assign status_to_fifo_to_host.oldestWriteIdx = oldest_write_idx;


    typedef enum
    {
        STATE_RD_POLL,
        STATE_RD_WAIT
    }
    t_STATE_READER;
    t_STATE_READER state_rd;
    t_STATE_READER next_state_rd;

    t_read_metadata reader_meta_req;

    // Unpack read response metadata
    t_read_metadata reader_meta_rsp;
    assign reader_meta_rsp = unpack_read_metadata(rx0.hdr);

    // Compute when a read response is available
    logic reader_data_rdy;
    assign reader_data_rdy = rx0.rdValid &&
                             reader_meta_rsp.isRead &&
                             reader_meta_rsp.isHeader;

    // View incoming read data as a vector of 32 bit objects
    t_cci_cldata_vec32 read_data_vec32;
    assign read_data_vec32 = rx0.data;


    //
    // Update FIFO pointers from host
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            newest_read_line_idx <= 0;
            oldest_write_idx <= 0;
        end
        else if (reader_data_rdy)
        begin
            // New read data present!
            newest_read_line_idx <= read_data_vec32[0];
            oldest_write_idx <= read_data_vec32[1];

            assert (state_rd == STATE_RD_WAIT) else
                $fatal("qa_drv_status_manager: Read response while not waiting for read!");
        end
    end


    //
    // Update state for next cycle
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state_rd <= STATE_RD_POLL;
        end
        else
        begin
            state_rd <= next_state_rd;
        end
    end

    always_comb
    begin
        //
        // Poll the CTRL line holding the read head pointer and write credits.
        //
        status_mgr_req.readHeader = 0;
        status_mgr_req.readHeader.req_type = eREQ_RDLINE_S;
        status_mgr_req.readHeader.address =
            ctrl_line_offset_to_addr(CTRL_OFFSET_POLL_STATE);

        reader_meta_req.reserved = 1'b0;
        reader_meta_req.isRead   = 1'b1;
        reader_meta_req.isHeader = 1'b1;
        reader_meta_req.robAddr  = 0;
        status_mgr_req.readHeader.mdata = pack_read_metadata(reader_meta_req);

        if (state_rd == STATE_RD_POLL)
        begin
            //
            // IDLE: Request a read
            //
            status_mgr_req.read.request = csr.hc_ctrl_frame_valid;

            // Wait for the read response if read was granted.
            next_state_rd = read_grant.statusGrant ? STATE_RD_WAIT : STATE_RD_POLL;
        end
        else
        begin
            //
            // READ REQUESTED: Wait for data.
            //
            status_mgr_req.read.request = 0;

            next_state_rd = reader_data_rdy ? STATE_RD_POLL : STATE_RD_WAIT;
        end
    end


    //=================================================================
    // Status WRITER FSM
    //=================================================================

    typedef enum
    {
        STATE_WR_INIT,
        STATE_WR_ACTIVE
    }
    t_STATE_WRITER;
    t_STATE_WRITER state_wr;
    t_STATE_WRITER next_state_wr;

    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            state_wr <= STATE_WR_INIT;
        end
        else
        begin
            state_wr <= next_state_wr;
        end
    end

    always_comb
    begin
        next_state_wr = state_wr;

        // Very simple protocol.  Only one thing may be active at a time.
        // No other requests may be processed while in STATE_WR_INIT.
        if (write_grant.statusGrant)
        begin
            next_state_wr = STATE_WR_ACTIVE;
        end
        else if (csr.hc_enable_test != 0)
        begin
            // Signal the beginning of testing by writing again
            // to CTRL entry 0.  This is easily accomplished by returning
            // to STATE_WR_INIT.
            next_state_wr = STATE_WR_INIT;
        end
    end


    //=================================================================
    // FIFO state tracking
    //=================================================================

    // Last index the host knows about -- written to CTRL
    t_fifo_from_host_idx fifo_from_host_current_idx;
    t_fifo_to_host_idx   fifo_to_host_current_idx;

    // Request write to CTRL of an updated index
    t_fifo_from_host_idx fifo_from_host_oldest_read_idx;
    t_fifo_to_host_idx   fifo_to_host_next_write_idx;

    // Need to update the status line?
    logic need_fifo_status_update;

    // Was a status line write sent to the write arbiter this cycle?
    logic requested_fifo_status_update;

    // Monitor one bit in the index to decide when to send credit.  Pick
    // a bit that balances reducing writes with sending credit early enough.
    localparam MONITOR_IDX_BIT = $bits(t_fifo_from_host_idx) - 3;

    //
    // Track the value last written to the CTRL status line and whether
    // a new write is required.
    //
    always_ff @(posedge clk)
    begin
        if (!reset_n)
        begin
            fifo_from_host_current_idx <= 0;
            fifo_to_host_current_idx <= 0;
            need_fifo_status_update <= 0;
        end
        else
        begin
            if (need_fifo_status_update)
            begin
                // Already need a write to CTRL.  Did it happen?
                if (requested_fifo_status_update && write_grant.statusGrant)
                begin
                    // Yes.  Record the value written.
                    need_fifo_status_update <= 0;
                    fifo_from_host_current_idx <= fifo_from_host_oldest_read_idx;
                    fifo_to_host_current_idx <= fifo_to_host_next_write_idx;
                end
            end
            else
            begin
                // Is a write needed?  Trigger write when the counter has changed
                // enough.
                need_fifo_status_update <=
                    (fifo_from_host_oldest_read_idx[MONITOR_IDX_BIT] !=
                     fifo_from_host_current_idx[MONITOR_IDX_BIT]) ||
                    (fifo_to_host_next_write_idx != fifo_to_host_current_idx);
            end
        end
    end
    
    // Buffer next_read_line_idx in a register for FPGA timing
    always_ff @(posedge clk)
    begin
        fifo_from_host_oldest_read_idx <=
            fifo_from_host_to_status.oldestReadLineIdx;

        fifo_to_host_next_write_idx <=
            fifo_to_host_to_status.nextWriteIdx;
    end

    // The FIFO status to write to CTRL
    t_cci_cldata fifo_status;
    assign fifo_status = t_cci_cldata'({ 32'(fifo_to_host_next_write_idx),
                                         32'(fifo_from_host_oldest_read_idx) });


    //=================================================================
    // create CCI Tx1 transaction (write to CTRL)
    //=================================================================

    int offset;
    t_cci_cldata data;

    always_comb
    begin
        requested_fifo_status_update = 0;

        data = fifo_status;

        if (state_wr != STATE_WR_ACTIVE)
        begin
            // Configuration is the sizes of the read and write buffers
            offset = CTRL_OFFSET_CFG;
            data[63:0] = { 32'(t_fifo_to_host_idx'(~0)),
                           32'(t_fifo_from_host_idx'(~0)) };

            // Wait until the CTRL is valid!
            status_mgr_req.write.request = csr.hc_ctrl_frame_valid;
        end
        else
        begin
            // FIFO state update
            offset = CTRL_OFFSET_FIFO_STATE;
            status_mgr_req.write.request = need_fifo_status_update;
            requested_fifo_status_update = need_fifo_status_update;
        end

        status_mgr_req.writeHeader = 0;
        status_mgr_req.writeHeader.req_type = eREQ_WRLINE_I;
        status_mgr_req.writeHeader.address =
            ctrl_line_offset_to_addr(offset);
        status_mgr_req.data = data;
    end
    
    always @(posedge clk)
    begin
        if (QA_DRIVER_DEBUG)
        begin  
            if (status_mgr_req.write.request)
              $display("Status writer attempts to write 0x%h to CL 0x%h", status_mgr_req.data, status_mgr_req.writeHeader.address);
            if (write_grant.statusGrant)
              $display("Status writer write request granted");        
        end
    end

endmodule
