//
// Copyright (c) 2015, Intel Corporation
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
// FIFO --
//   A FIFO with N_ENTRIES storage elements and signaling almostFull when
//   THRESHOLD or fewer slots are free.
//

module qa_drv_prim_fifo_lutram
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1
    )
   (
    input  logic clk,
    input  logic resetb,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic                     enq_en,
    output logic                     notFull,
    output logic                     almostFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic                     deq_en,
    output logic                     notEmpty
    );
     
    // Pointer to head/tail in storage
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;
    // Counter of active entries, leaving room to represent both 0 and N_ENTRIES.
    typedef logic [$clog2(N_ENTRIES+1)-1 : 0] t_COUNTER;

    // synthesis attribute ram_style of data is distributed
    reg [N_DATA_BITS-1 : 0] data[0 : N_ENTRIES-1] /* synthesis ramstyle = "MLAB, no_rw_check" */;

    t_IDX wr_idx;
    t_IDX rd_idx;

    t_COUNTER valid_cnt;
    t_COUNTER valid_cnt_next;

    assign first = data[rd_idx];

    // Write pointer advances on ENQ
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            wr_idx <= 1'b0;
        end
        else if (enq_en)
        begin
            data[wr_idx] <= enq_data;
            wr_idx <= (wr_idx == t_IDX'(N_ENTRIES-1)) ? 0 : wr_idx + 1;

            assert (notFull) else
                $fatal("qa_drv_prom_fifo_lutram: ENQ to full FIFO!");
        end
    end

    // Read pointer advances on DEQ
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            rd_idx <= 1'b0;
        end
        else if (deq_en)
        begin
            rd_idx <= (rd_idx == t_IDX'(N_ENTRIES-1)) ? 0 : rd_idx + 1;

            assert (notEmpty) else
                $fatal("qa_drv_prom_fifo_lutram: DEQ from empty FIFO!");
        end
    end

    // Update count of live values
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            valid_cnt <= t_COUNTER'(0);
            notFull <= 1'b1;
            almostFull <= 1'b0;
            notEmpty <= 1'b0;
        end
        else
        begin
            valid_cnt <= valid_cnt_next;
            notFull <= (valid_cnt_next != t_COUNTER'(N_ENTRIES));
            almostFull <= (valid_cnt_next >= t_COUNTER'(N_ENTRIES - THRESHOLD));
            notEmpty <= (valid_cnt_next != t_COUNTER'(0));
        end
    end

    always_comb
    begin
        valid_cnt_next = valid_cnt;

        if (deq_en && ! enq_en)
        begin
            valid_cnt_next = valid_cnt_next - t_COUNTER'(1);
        end
        else if (enq_en && ! deq_en)
        begin
            valid_cnt_next = valid_cnt_next + t_COUNTER'(1);
        end
    end

endmodule // qa_drv_prim_fifo_lutram
