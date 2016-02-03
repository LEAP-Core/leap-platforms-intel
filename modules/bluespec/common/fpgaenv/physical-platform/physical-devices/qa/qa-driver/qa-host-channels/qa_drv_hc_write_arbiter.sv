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

`include "qa_drv_hc.vh"


module qa_drv_hc_write_arbiter
   (
    input logic clk,
    input logic reset,

    input  t_qa_drv_hc_csrs       csr,
   
    input  t_frame_arb            frame_writer,
    input  t_frame_arb            frame_reader,
    input  t_frame_arb            status_mgr_req,
    output t_channel_grant_arb    write_grant,
   
    output t_if_cci_c1_Tx         tx1,
    input  logic                  tx1_almostfull
    );

    // The reader gates can issue with csr.hc_en.  The writer can't do this
    // since the FPGA must write the configuration information to CTRL[0].
    logic can_issue;

    t_cci_ReqMemHdr header;
    t_cci_cldata data;   
    logic wrvalid;
    
    typedef enum logic {FAVOR_FRAME_READER, FAVOR_FRAME_WRITER} state_t;
    
    state_t state;
    state_t next_state;

    // Issue control FSM
    qa_drv_hc_can_issue issue_control
       (
        .clk,
        .reset,
        .almostfull(tx1_almostfull),
        .can_issue,
        .issue(write_grant.readerGrant | write_grant.writerGrant)
        );

    // FSM state
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            state <= FAVOR_FRAME_READER;
        end
        else
        begin
            state <= next_state;
        end
    end

    always_comb
    begin
        if(write_grant.writerGrant)
          next_state = FAVOR_FRAME_WRITER;
        else
          next_state = FAVOR_FRAME_READER;
    end


    // Set outgoing write control packet.
    always_comb
    begin
        write_grant.canIssue = can_issue;
        write_grant.readerGrant = 0;
        write_grant.writerGrant = 0;
        write_grant.statusGrant = 0;                                           

        header  = status_mgr_req.writeHeader;
        data    = status_mgr_req.data;
        
        if (status_mgr_req.write.request)
        begin
            write_grant.statusGrant = can_issue;
        end                                           
        else if (frame_reader.write.request &&
                 (state == FAVOR_FRAME_READER || !frame_writer.write.request))
        begin
            header  = frame_reader.writeHeader;
            data    = frame_reader.data;
            
            write_grant.readerGrant = can_issue;                                           
        end
        else if (frame_writer.write.request)
        begin
            header  = frame_writer.writeHeader;
            data    = frame_writer.data;
            write_grant.writerGrant = can_issue;                                           
        end

        wrvalid = (frame_reader.write.request || frame_writer.write.request ||
                   status_mgr_req.write.request) && can_issue;   
    end

    // Register outgoing control packet.
    t_if_cci_c1_Tx tx1_upd;
    always_ff @(posedge clk)
    begin
        tx1 <= tx1_upd;
    end

    always_comb
    begin
        tx1_upd = cci_c1TxClearValids();
        tx1_upd.hdr = header;
        tx1_upd.data = data;
        tx1_upd.wrValid = wrvalid;

        if (! tx1_upd.wrValid)
        begin
            // req_type should match one-hot valid signal
            tx1_upd.hdr.req_type = t_cci_req'(0);
        end
    end


    // Some assertions
    always_comb
    begin
        if (write_grant.writerGrant && write_grant.readerGrant && ! reset && ~clk)
        begin
            $display("Double grant of reader %d %d.", write_grant.readerGrant, write_grant.writerGrant);        
            $finish;           
        end
    end
    
endmodule // qa_drv_hc_write_arbiter

