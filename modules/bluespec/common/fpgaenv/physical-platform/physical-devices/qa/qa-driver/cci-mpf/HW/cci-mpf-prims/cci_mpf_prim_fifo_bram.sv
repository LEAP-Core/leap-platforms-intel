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
//   THRESHOLD or fewer slots are free, stored in block RAM.
//

module cci_mpf_prim_fifo_bram
  #(
    parameter N_DATA_BITS = 32,
    parameter N_ENTRIES = 2,
    parameter THRESHOLD = 1,

    // Register output if non-zero
    parameter REGISTER_OUTPUT = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic [N_DATA_BITS-1 : 0] enq_data,
    input  logic                     enq_en,
    output logic                     notFull,
    output logic                     almostFull,

    output logic [N_DATA_BITS-1 : 0] first,
    input  logic                     deq_en,
    output logic                     notEmpty
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    t_idx enq_data_idx;
    logic first_deq;
    logic first_rdy;
    t_idx first_idx;

    //
    // BRAM FIFO control logic
    //
    cci_mpf_prim_fifo_bram_ctrl
      #(
        .N_ENTRIES(N_ENTRIES),
        .THRESHOLD(THRESHOLD)
        )
      ctrl
       (
        .clk,
        .reset,

        .enq_en,
        .enq_data_idx,
        .notFull,
        .almostFull,

        .deq_en(first_deq),
        .notEmpty(first_rdy),
        .first_idx
        );

    //
    // BRAM FIFO data and buffering output FIFO
    //
    cci_mpf_prim_fifo_bram_data
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(N_ENTRIES),
        .REGISTER_OUTPUT(REGISTER_OUTPUT)
        )
      data
       (
        .clk,
        .reset,

        .enq_en,
        .enq_data_idx,
        .enq_data,

        .deq_en,
        .notEmpty,
        .first,

        .first_rdy,
        .first_deq,
        .first_idx
        );

endmodule // cci_mpf_prim_fifo_bram



module cci_mpf_prim_fifo_bram_ctrl
  #(
    parameter N_ENTRIES = 32,
    parameter THRESHOLD = 1
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic enq_en,
    output logic [$clog2(N_ENTRIES)-1 : 0] enq_data_idx, // Index of newest entry
    output logic notFull,
    output logic almostFull,

    input  logic deq_en,
    output logic notEmpty,
    output logic [$clog2(N_ENTRIES)-1 : 0] first_idx     // Index of oldest entry
    );
     
    // Pointer to head/tail in storage
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;
    // Counter of active entries, leaving room to represent both 0 and N_ENTRIES.
    typedef logic [$clog2(N_ENTRIES+1)-1 : 0] t_counter;

    t_idx wr_idx;
    assign enq_data_idx = wr_idx;
    t_idx rd_idx;
    assign first_idx = rd_idx;

    t_counter valid_cnt;
    t_counter valid_cnt_next;

    // Write pointer advances on ENQ
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            wr_idx <= 1'b0;
        end
        else if (enq_en)
        begin
            wr_idx <= (wr_idx == t_idx'(N_ENTRIES-1)) ? 0 : wr_idx + 1;

            assert (notFull) else
                $fatal("cci_mpf_prim_fifo_lutram: ENQ to full FIFO!");
        end
    end

    // Read pointer advances on DEQ
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            rd_idx <= 1'b0;
        end
        else if (deq_en)
        begin
            rd_idx <= (rd_idx == t_idx'(N_ENTRIES-1)) ? 0 : rd_idx + 1;

            assert (notEmpty) else
                $fatal("cci_mpf_prim_fifo_lutram: DEQ from empty FIFO!");
        end
    end

    // Update count of live values
    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            valid_cnt <= t_counter'(0);
            notFull <= 1'b1;
            almostFull <= 1'b0;
            notEmpty <= 1'b0;
        end
        else
        begin
            valid_cnt <= valid_cnt_next;
            notFull <= (valid_cnt_next != t_counter'(N_ENTRIES));
            almostFull <= (valid_cnt_next >= t_counter'(N_ENTRIES - THRESHOLD));
            notEmpty <= (valid_cnt_next != t_counter'(0));
        end
    end

    always_comb
    begin
        valid_cnt_next = valid_cnt;

        if (deq_en && ! enq_en)
        begin
            valid_cnt_next = valid_cnt_next - t_counter'(1);
        end
        else if (enq_en && ! deq_en)
        begin
            valid_cnt_next = valid_cnt_next + t_counter'(1);
        end
    end

endmodule // cci_mpf_prim_fifo_bram_ctrl



//
// Manage the data half of the FIFO.  When the control pipeline indicates
// output is ready this module retrieves the value from memory and then
// routes the value through a register FIFO.  The extra buffering in the
// register FIFO breaks the combinational loop between deq of the oldest
// value and starting the memory read of the next oldest value, which is
// a multi-cycle pipelined block RAM read.
//
module cci_mpf_prim_fifo_bram_data
  #(
    parameter N_DATA_BITS = 64,
    parameter N_ENTRIES = 32,
    parameter REGISTER_OUTPUT = 0
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic enq_en,
    input  logic [$clog2(N_ENTRIES)-1 : 0] enq_data_idx,
    input  logic [N_DATA_BITS-1 : 0] enq_data,

    input  logic deq_en,                             // Deq first entry
    output logic notEmpty,                           // Is first entry ready?
    output logic [N_DATA_BITS-1 : 0] first,          // Data for first entry

    // Signals connected to the FIFO control module
    input  logic first_rdy,                          // Is first entry ready?
    output logic first_deq,
    input  logic [$clog2(N_ENTRIES)-1 : 0] first_idx // Index of first entry
    );

    typedef logic [N_DATA_BITS-1 : 0] t_data;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    t_data mem_first;
    logic fifo_full;

    // Transfer from BRAM to register output  FIFO when data is ready
    // and the output FIFO has space for new data plus whatever may be
    // in flight already.
    assign first_deq = first_rdy && ! fifo_full;

    // Record when memory is read so the result can be written to the FIFO
    // at the right time.
    logic did_first_deq;
    logic did_first_deq_q;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            did_first_deq <= 1'b0;
            did_first_deq_q <= 1'b0;
        end
        else
        begin
            did_first_deq <= first_deq;
            did_first_deq_q <= did_first_deq;
        end
    end


    //
    // Storage where data will be sorted.  Port 0 is used for writes and
    // port 1 for reads.
    //
    cci_mpf_prim_ram_dualport
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(1)
        )
      memData
       (
        .clk0(clk),
        .addr0(enq_data_idx),
        .wen0(enq_en),
        .wdata0(enq_data),
        .rdata0(),

        .clk1(clk),
        .addr1(first_idx),
        .wen1(1'b0),
        .wdata1(N_DATA_BITS'(0)),
        .rdata1(mem_first)
        );

    //
    // Output FIFO stage.
    //
    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(N_DATA_BITS),
        .N_ENTRIES(4),
        .THRESHOLD(2),
        .REGISTER_OUTPUT(REGISTER_OUTPUT)
        )
      fifo
       (
        .clk,
        .reset,
        .enq_data(mem_first),
        .enq_en(did_first_deq_q),
        .notFull(),
        .almostFull(fifo_full),
        .first,
        .deq_en,
        .notEmpty
        );

endmodule // cci_mpf_prim_fifo_bram_data
