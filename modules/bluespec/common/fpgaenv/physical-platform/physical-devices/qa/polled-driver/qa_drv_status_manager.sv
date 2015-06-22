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

module qa_drv_status_manager
    (input logic clk,
     input logic resetb,

     input  rx_c0_t              rx0,

     input  t_CSR_AFU_STATE      csr,
     output frame_arb_t          status_mgr_req,
     input  channel_grant_arb_t  read_grant,
     input  channel_grant_arb_t  write_grant,

     input  t_TO_STATUS_MGR_FIFO_FROM_HOST   fifo_from_host_to_status,
     output t_FROM_STATUS_MGR_FIFO_FROM_HOST status_to_fifo_from_host,

     input  t_TO_STATUS_MGR_FIFO_TO_HOST     fifo_to_host_to_status,
     output t_FROM_STATUS_MGR_FIFO_TO_HOST   status_to_fifo_to_host,

     input  t_TO_STATUS_MGR_TESTER           tester_to_status,

     output t_SREG_ADDR           sreg_req_addr,
     output logic                 sreg_req_rdy,
     input  t_SREG                sreg_rsp,
     input  logic                 sreg_rsp_enable
    );

    //
    // Offsets in DSM used for communicating state with the host.
    //
    // THESE OFFSETS MUST MATCH THE HOST!
    //
    localparam DSM_OFFSET_AFU_ID     = t_DSM_LINE_OFFSET'(0);
    localparam DSM_OFFSET_SREG_RSP   = t_DSM_LINE_OFFSET'(1);
    localparam DSM_OFFSET_DEBUG_RSP  = t_DSM_LINE_OFFSET'(2);
    localparam DSM_OFFSET_FIFO_STATE = t_DSM_LINE_OFFSET'(3);
    localparam DSM_OFFSET_POLL_STATE = t_DSM_LINE_OFFSET'(4);

    //
    // AFU ID is used at the beginning of a run to tell the host the FPGA
    // is alive.
    //
    t_CACHE_LINE_VEC32 afu_id;
    assign afu_id[0] = 32'haced0000;
    assign afu_id[1] = 32'haced0001;
    assign afu_id[2] = 32'haced0002;
    assign afu_id[3] = 32'haced0003;

    // Communicate information about the hardware configuration in the remainder
    // of the afu_id line:

    // Number of lines in the FIFO from the host
    assign afu_id[4] = t_FIFO_FROM_HOST_IDX'(~0);
    // Number of lines in the FIFO to the host
    assign afu_id[5] = t_FIFO_TO_HOST_IDX'(~0);
    
    // Clear the rest of afu_id
    genvar i;
    generate
        for (i = 6; i < N_BIT32_PER_CACHE_LINE; i++)
        begin : gen_afu_id
            assign afu_id[i] = 32'd0;
        end
    endgenerate


    //
    // Debugging state.
    //

    // Request (from the CSR write)
    t_AFU_DEBUG_REQ debug_req;
    // Response (muxed from other modules below)
    t_AFU_DEBUG_RSP debug_rsp;
    // The full message to be written to DSM line 0.
    t_CACHE_LINE debug_rsp_line;
    assign debug_rsp_line = {debug_req, debug_rsp};

    // Status register response from client
    t_SREG sreg_client_rsp;
    t_CACHE_LINE sreg_rsp_line;

    
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
    t_FIFO_FROM_HOST_IDX newest_read_line_idx;
    assign status_to_fifo_from_host.newest_read_line_idx = newest_read_line_idx;

    t_FIFO_TO_HOST_IDX oldest_write_line_idx;
    assign status_to_fifo_to_host.oldest_write_line_idx = oldest_write_line_idx;


    typedef enum
    {
        STATE_RD_POLL,
        STATE_RD_WAIT
    }
    t_STATE_READER;
    t_STATE_READER state_rd;
    t_STATE_READER next_state_rd;

    read_metadata_t reader_meta_req;

    // Unpack read response metadata
    read_metadata_t reader_meta_rsp;
    assign reader_meta_rsp = unpack_read_metadata(rx0.header);

    // Compute when a read response is available
    logic reader_data_rdy;
    assign reader_data_rdy = rx0.rdvalid &&
                             reader_meta_rsp.is_read &&
                             reader_meta_rsp.is_header;

    // View incoming read data as a vector of 32 bit objects
    t_CACHE_LINE_VEC32 read_data_vec32;
    assign read_data_vec32 = rx0.data;


    //
    // Update FIFO pointers from host
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            newest_read_line_idx <= 0;
            oldest_write_line_idx <= 0;
        end
        else if (reader_data_rdy)
        begin
            // New read data present!
            newest_read_line_idx <= read_data_vec32[0];
            oldest_write_line_idx <= read_data_vec32[1];

            assert (state_rd == STATE_RD_WAIT) else
                $fatal("qa_drv_status_manager: Read response while not waiting for read!");
        end
    end


    //
    // Update state for next cycle
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
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
        // Poll the DSM line holding the read head pointer and write credits.
        //
        status_mgr_req.read_header = 0;
        status_mgr_req.read_header.request_type = RdLine;
        status_mgr_req.read_header.address =
            dsm_line_offset_to_addr(DSM_OFFSET_POLL_STATE, csr.afu_dsm_base);

        reader_meta_req.is_read   = 1'b1;
        reader_meta_req.is_header = 1'b1;
        reader_meta_req.rob_addr  = 0;
        status_mgr_req.read_header.mdata = pack_read_metadata(reader_meta_req);

        if (state_rd == STATE_RD_POLL)
        begin
            //
            // IDLE: Request a read
            //
            status_mgr_req.read.request = 1;

            // Wait for the read response if read was granted.
            next_state_rd = read_grant.status_grant ? STATE_RD_WAIT : STATE_RD_POLL;
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
        STATE_WR_IDLE,
        STATE_WR_DEBUG,
        STATE_WR_STATUS
    }
    t_STATE_WRITER;
    t_STATE_WRITER state_wr;
    t_STATE_WRITER next_state_wr;

    always_ff @(posedge clk)
    begin
        if (!resetb)
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
        // No other requests may be processed while in STATE_WR_INIT.  No new
        // DEBUG requests will be noticed until the current one completes.
        if (write_grant.status_grant)
        begin
            next_state_wr = STATE_WR_IDLE;
        end
        else if (csr.afu_enable_test != 0)
        begin
            // Signal the beginning of testing by writing the AFU ID again
            // to DSM entry 0.  This is easily accomplished by returning
            // to STATE_WR_INIT.
            next_state_wr = STATE_WR_INIT;
        end
        else if (csr.afu_trigger_debug.idx != 0)
        begin
            next_state_wr = STATE_WR_DEBUG;
        end
        else if (sreg_rsp_enable)
        begin
            next_state_wr = STATE_WR_STATUS;
        end
    end


    //=================================================================
    // FIFO state tracking
    //=================================================================

    // Last index the host knows about -- written to DSM
    t_FIFO_FROM_HOST_IDX fifo_from_host_current_idx;
    t_FIFO_TO_HOST_IDX   fifo_to_host_current_idx;

    // Request write to DSM of an updated index
    t_FIFO_FROM_HOST_IDX fifo_from_host_oldest_read_idx;
    t_FIFO_TO_HOST_IDX   fifo_to_host_next_write_idx;

    // Need to update the status line?
    logic need_fifo_status_update;

    // Was a status line write sent to the write arbiter this cycle?
    logic requested_fifo_status_update;

    // Monitor one bit in the index to decide when to send credit.  Pick
    // a bit that balances reducing writes with sending credit early enough.
    localparam MONITOR_IDX_BIT = $bits(t_FIFO_FROM_HOST_IDX) - 3;

    //
    // Track the value last written to the DSM status line and whether
    // a new write is required.
    //
    always_ff @(posedge clk)
    begin
        if (!resetb)
        begin
            fifo_from_host_current_idx <= 0;
            fifo_to_host_current_idx <= 0;
            need_fifo_status_update <= 0;
        end
        else
        begin
            if (need_fifo_status_update)
            begin
                // Already need a write to DSM.  Did it happen?
                if (requested_fifo_status_update && write_grant.status_grant)
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
            fifo_from_host_to_status.oldest_read_line_idx;

        fifo_to_host_next_write_idx <=
            fifo_to_host_to_status.next_write_line_idx;
    end

    // The FIFO status to write to DSM
    t_CACHE_LINE fifo_status;
    assign fifo_status = t_CACHE_LINE'({ 32'(fifo_to_host_next_write_idx),
                                         32'(fifo_from_host_oldest_read_idx) });


    //=================================================================
    // create CCI Tx1 transaction (write to DSM)
    //=================================================================

    t_DSM_LINE_OFFSET offset;
    t_CACHE_LINE data;

    always_comb
    begin
        requested_fifo_status_update = 0;

        if (state_wr != STATE_WR_IDLE)
        begin
            case (state_wr)
              STATE_WR_DEBUG:
                begin
                    offset = DSM_OFFSET_DEBUG_RSP;
                    data = debug_rsp_line;
                end
              STATE_WR_STATUS:
                begin
                    offset = DSM_OFFSET_SREG_RSP;
                    data = sreg_rsp_line;
                end
              default:
                begin
                    offset = DSM_OFFSET_AFU_ID;
                    data = afu_id;
                end
            endcase

            // Wait until the DSM is valid!
            status_mgr_req.write.request = csr.afu_dsm_base_valid;
        end
        else
        begin
            // FIFO state update
            offset = DSM_OFFSET_FIFO_STATE;
            data = fifo_status;
            status_mgr_req.write.request = need_fifo_status_update;
            requested_fifo_status_update = need_fifo_status_update;
        end

        status_mgr_req.write_header = 0;
        status_mgr_req.write_header.request_type = WrThru;
        status_mgr_req.write_header.address =
            dsm_line_offset_to_addr(offset, csr.afu_dsm_base);
        status_mgr_req.data = data;
    end
    
    always@(negedge clk)
    begin
        if (QA_DRIVER_DEBUG)
        begin  
            if (status_mgr_req.write.request)
              $display("Status writer attempts to write 0x%h to CL 0x%h", status_mgr_req.data, status_mgr_req.write_header.address);
            if (write_grant.status_grant)
              $display("Status writer write request granted");        
        end
    end
    

    //=================================================================
    //
    // Client status registers.
    //
    //=================================================================

    assign sreg_req_addr = csr.afu_sreg_req.addr;
    assign sreg_req_rdy = csr.afu_sreg_req.enable;

    always_comb
    begin
        sreg_rsp_line = t_CACHE_LINE'(sreg_client_rsp);
        sreg_rsp_line[$size(sreg_rsp_line)-1] = 1'b1;
    end

    always@(negedge clk)
    begin
        if (sreg_rsp_enable)
        begin
            sreg_client_rsp <= sreg_rsp;
        end
    end


    //=================================================================
    //
    // Debugging state dump, triggered by CSR_AFU_TRIGGER_DEBUG.
    //
    //=================================================================

    // What debug info to write?
    always_comb
    begin
        case (debug_req.idx)
            1:
              debug_rsp = fifo_from_host_to_status.dbg_fifo_state;
            2:
              debug_rsp = fifo_to_host_to_status.dbg_fifo_state;
            3:
              debug_rsp = tester_to_status.dbg_tester;
            default:
              debug_rsp = fifo_from_host_to_status.dbg_fifo_state;
        endcase
    end

    // Grab the index of debugging requests.  It is illegal in the debugging
    // protocol to trigger a new request before the previous one is done,
    // making this logic simple.
    always_ff @(posedge clk)
    begin
        if (csr.afu_trigger_debug.idx != 0)
        begin
            debug_req <= csr.afu_trigger_debug;
        end
    end

endmodule
