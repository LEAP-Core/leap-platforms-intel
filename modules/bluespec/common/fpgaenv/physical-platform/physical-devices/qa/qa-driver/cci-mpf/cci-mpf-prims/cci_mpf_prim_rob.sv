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
// ROB that returns data FIFO by sorting out of order arrival of
// the payload.  The ROB combines two pieces of data with each entry:
// meta-data that is supplied at the time an index is allocated and the
// late-arriving data.  Both are returned together through first and first_meta.
// Within the driver this is typically used to combine a parent's Mdata
// field for the response header in combination with read data.
//

module cci_mpf_prim_rob
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset,

    // Add a new entry to the ROB.  No payload, just control.
    // The ROB returns a handle -- the index where the payload should
    // be written.
    input  logic enq_en,                            // Allocate an entry
    input  logic [N_META_BITS-1 : 0] enqMeta,       // Save meta-data for new entry
    output logic notFull,                           // Is ROB full?
    output logic [$clog2(N_ENTRIES)-1 : 0] enqIdx,  // Index of new entry

    // Payload write.  No ready signal.  The ROB must always be ready
    // to receive data.
    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,
    input  logic [N_DATA_BITS-1 : 0] enqData,

    // Ordered output
    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    output logic [N_DATA_BITS-1 : 0] first,         // Data for oldest entry
    output logic [N_META_BITS-1 : 0] firstMeta      // Meta-data for oldest entry
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    logic oldest_deq;
    logic oldest_rdy;
    t_idx oldestIdx;

    //
    // ROB control logic
    //
    cci_mpf_prim_rob_ctrl
      #(
        .N_ENTRIES(N_ENTRIES),
        .MIN_FREE_SLOTS(MIN_FREE_SLOTS)
        )
      ctrl
       (
        .clk,
        .reset,
        .enq_en,
        .notFull,
        .enqIdx,
        .enqData_en,
        .enqDataIdx,

        .oldest_deq,
        .oldest_rdy,
        .oldestIdx
        );

    //
    // ROB data and buffering output FIFO
    //
    cci_mpf_prim_rob_data
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_META_BITS(N_META_BITS)
        )
      data
       (
        .clk,
        .reset,
        .enq_en,
        .enqMeta,
        .enqMetaIdx(enqIdx),
        .enqData_en,
        .enqDataIdx,
        .enqData,
        .deq_en,
        .notEmpty,
        .first,
        .firstMeta,

        .oldestIdx,
        .oldest_rdy,
        .oldest_deq
        );

endmodule // cci_mpf_prim_rob



module cci_mpf_prim_rob_ctrl
  #(
    parameter N_ENTRIES = 32,

    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic enq_en,                              // Allocate an entry
    output logic notFull,                             // Is ROB full?
    output logic [$clog2(N_ENTRIES)-1 : 0] enqIdx,    // Index of new entry

    input  logic enqData_en,                          // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,

    input  logic oldest_deq,                          // Deq oldest entry
    output logic oldest_rdy,                          // Is oldest entry ready?
    output logic [$clog2(N_ENTRIES)-1 : 0] oldestIdx  // Index of oldest entry
    );

    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    // Index logic in a space 1 bit larger than the true space
    // in order to accommodate pointer comparison as pointers wrap.
    typedef logic [$clog2(N_ENTRIES) : 0] t_idx_nowrap;

    t_idx newest;
    t_idx oldest;
    assign oldestIdx = oldest;

    // notFull is true as long as there are at least MIN_FREE_SLOTS available
    // at the end of the ring buffer. The computation is complicated by the
    // wrapping pointer.
    logic newest_ge_oldest;
    assign newest_ge_oldest = (newest >= oldest);
    assign notFull =
        ({1'b0, newest} + t_idx_nowrap'(MIN_FREE_SLOTS)) < {newest_ge_oldest, oldest};

    // enq allocates a slot and returns the index of the slot.
    assign enqIdx = newest;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            newest <= 0;
        end
        else if (enq_en)
        begin
            newest <= newest + 1;

            assert ((newest + t_idx'(1)) != oldest) else
                $fatal("cci_mpf_prim_rob: Can't ENQ when FULL!");
            assert ((N_ENTRIES & (N_ENTRIES - 1)) == 0) else
                $fatal("cci_mpf_prim_rob: N_ENTRIES must be a power of 2!");
        end
    end


    // Bump the oldest pointer when the oldest entry is returned to the
    // client.
    always_ff @(posedge clk)
    begin
        if (reset)
            oldest <= 0;
        else
        begin
            oldest <= oldest + oldest_deq;
        end
    end


    // Track data arrival
    logic [N_ENTRIES-1 : 0] dataValid;
    logic [N_ENTRIES-1 : 0] dataValid_q;

    // Small register with the two dataValid_q entries that are useful
    // this cycle.
    logic [1 : 0] dataValid_sub_q;
    logic oldest_deq_q;
    t_idx oldest_q;

    // Check one of two valid bits using registered state to determine
    // oldest_rdy, depending on whether the oldest entry was dequeued
    // last cycle.  This is the best balance of work across two cycles
    // that still maintains full throughput.
    assign oldest_rdy = dataValid_sub_q[oldest_deq_q];

    // Track valid data
    always_comb
    begin
        dataValid = dataValid_q;

        // Clear on completion. Actually, one cycle later for timing.
        if (oldest_deq_q)
        begin
            dataValid[oldest_q] = 1'b0;
        end

        // Set when data arrives.
        if (enqData_en)
        begin
            dataValid[enqDataIdx] = 1'b1;
        end
    end

    // Local reset for output data valid registers since dataValid_q is
    // large enough to be a timing problem. No output can be ready the
    // first cycle after reset is complete, so the delay isn't a problem.
    logic reset_q;
    always_ff @(posedge clk)
    begin
        reset_q <= reset;
    end

    always_ff @(posedge clk)
    begin
        if (reset_q)
        begin
            dataValid_q <= N_ENTRIES'(0);
            dataValid_sub_q <= 2'b0;
            oldest_deq_q <= 1'b0;
        end
        else
        begin
            dataValid_q <= dataValid;
            oldest_deq_q <= oldest_deq;

            // Record enough state to compute oldest_rdy in the next cycle
            // in a method that is relatively independent of computation
            // this cycle.
            dataValid_sub_q <= { dataValid_q[t_idx'(oldest + 1)],
                                 dataValid_q[oldest] };
        end

        oldest_q <= oldest;
    end

    always_ff @(negedge clk)
    begin
        if (! reset)
        begin
            assert(! oldest_deq || oldest_rdy) else
              $fatal("cci_mpf_prim_rob: Can't DEQ when EMPTY!");
        end
    end

endmodule // cci_mpf_prim_rob_ctrl


//
// Manage the data half of the ROB.  When the control pipeline indicates
// output is ready this module retrieves the value from memory and then
// routes the value through a FIFO.  The extra buffering in the FIFO
// breaks the combinational loop between deq of the oldest value and
// starting the memory read of the next oldest value, which is a multi-
// cycle pipelined block RAM read.
//
module cci_mpf_prim_rob_data
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1
    )
   (
    input  logic clk,
    input  logic reset,

    input  logic enq_en,                            // Allocate an entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqMetaIdx,
    input  logic [N_META_BITS-1 : 0] enqMeta,       // Save meta-data for new entry

    input  logic enqData_en,                        // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx,
    input  logic [N_DATA_BITS-1 : 0] enqData,

    input  logic deq_en,                            // Deq oldest entry
    output logic notEmpty,                          // Is oldest entry ready?
    output logic [N_DATA_BITS-1 : 0] first,         // Data for oldest entry
    output logic [N_META_BITS-1 : 0] firstMeta,     // Meta-data for oldest entry

    // Signals connected to the ROB control module
    input  logic oldest_rdy,                        // Is oldest entry ready?
    output logic oldest_deq,
    input  logic [$clog2(N_ENTRIES)-1 : 0] oldestIdx  // Index of oldest entry
    );

    typedef logic [N_DATA_BITS-1 : 0] t_data;
    typedef logic [N_META_BITS-1 : 0] t_meta_data;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    t_data mem_first;
    t_meta_data mem_meta_first;

    logic fifo_full;

    // Transfer from ROB to FIFO when data is ready and the FIFO
    // has space for new data plus whatever may be in flight already.
    assign oldest_deq = oldest_rdy && ! fifo_full;

    // Record when memory is read so the result can be written to the FIFO
    // at the right time.
    logic did_oldest_deq;
    logic did_oldest_deq_q;

    always_ff @(posedge clk)
    begin
        if (reset)
        begin
            did_oldest_deq <= 1'b0;
            did_oldest_deq_q <= 1'b0;
        end
        else
        begin
            did_oldest_deq <= oldest_deq;
            did_oldest_deq_q <= did_oldest_deq;
        end
    end


    //
    // Storage where data will be sorted.  Port 0 is used for writes and
    // port 1 for reads.
    //
    cci_mpf_prim_dualport_ram
      #(
        .N_ENTRIES(N_ENTRIES),
        .N_DATA_BITS(N_DATA_BITS),
        .N_OUTPUT_REG_STAGES(1)
        )
      memData
       (
        .clk0(clk),
        .addr0(enqDataIdx),
        .wen0(enqData_en),
        .wdata0(enqData),
        .rdata0(),

        .clk1(clk),
        .addr1(oldestIdx),
        .wen1(1'b0),
        .wdata1(N_DATA_BITS'(0)),
        .rdata1(mem_first)
        );

    //
    // Meta-data memory.
    //
    generate
        if (N_META_BITS != 0)
        begin : genMeta
            cci_mpf_prim_dualport_ram
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(N_META_BITS),
                .N_OUTPUT_REG_STAGES(1)
                )
              memMeta
               (
                .clk0(clk),
                .addr0(enqMetaIdx),
                .wen0(enq_en),
                .wdata0(enqMeta),
                .rdata0(),

                .clk1(clk),
                .addr1(oldestIdx),
                .wen1(1'b0),
                .wdata1('x),
                .rdata1(mem_meta_first)
                );
        end
        else
        begin : noMeta
            assign mem_meta_first = 'x;
        end
    endgenerate

    //
    // Output FIFO stage.
    //
    cci_mpf_prim_fifo_lutram
      #(
        .N_DATA_BITS(N_META_BITS + N_DATA_BITS),
        .N_ENTRIES(4),
        .THRESHOLD(2)
        )
      fifo
       (
        .clk,
        .reset,
        .enq_data({ mem_meta_first, mem_first }),
        .enq_en(did_oldest_deq_q),
        .notFull(),
        .almostFull(fifo_full),
        .first({ firstMeta, first }),
        .deq_en,
        .notEmpty
        );

endmodule // cci_mpf_prim_rob_data
