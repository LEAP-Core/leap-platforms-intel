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
// Scoreboard that returns data FIFO by sorting out of order arrival of
// the payload.  The scoreboard combines two pieces of data with each entry:
// meta-data that is supplied at the time an index is allocated and the
// late-arriving data.  Both are returned together through first and first_meta.
// Within the driver this is typically used to combine a parent's Mdata
// field for the response header in combination with read data.
//

module qa_drv_prim_scoreboard
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic resetb,

    // Add a new entry to the scoreboard.  No payload, just control.
    // The scoreboard returns a handle -- the index where the payload should
    // be written.
    input  logic enq_en,                            // Allocate an entry
    input  logic [N_META_BITS-1 : 0] enqMeta,       // Save meta-data for new entry
    output logic notFull,                           // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] enqIdx,  // Index of new entry

    // Payload write.  No ready signal.  The scoreboard must always be ready
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

    typedef logic [N_DATA_BITS-1 : 0] t_DATA;
    typedef logic [N_META_BITS-1 : 0] t_META_DATA;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;

    // Index logic in a space 1 bit larger than the true space
    // in order to accommodate pointer comparison as pointers wrap.
    typedef logic [$clog2(N_ENTRIES) : 0] t_IDX_NOWRAP;

    typedef struct packed
    {
        t_DATA data;
        t_META_DATA meta;
    }
    t_OUTPUT_DATA;

    t_IDX newest;
    t_IDX oldest;
    t_IDX oldest_next;

    // Track data arrival
    reg [N_ENTRIES-1 : 0] dataValid;

    // notFull is true as long as there are at least MIN_FREE_SLOTS available
    // at the end of the ring buffer. The computation is complicated by the
    // wrapping pointer.
    logic newest_ge_oldest;
    assign newest_ge_oldest = (newest >= oldest);
    assign notFull =
        ({1'b0, newest} + t_IDX_NOWRAP'(MIN_FREE_SLOTS)) < {newest_ge_oldest, oldest};

    // enq allocates a slot and returns the index of the slot.
    assign enqIdx = newest;

    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            newest <= 0;
        end
        else if (enq_en)
        begin
            newest <= newest + 1;

            assert ((newest + t_IDX'(1)) != oldest) else
                $fatal("qa_drv_prim_scoreboard: Can't ENQ when FULL!");
            assert ((N_ENTRIES & (N_ENTRIES - 1)) == 0) else
                $fatal("qa_drv_prim_scoreboard: N_ENTRIES must be a power of 2!");
        end
    end


    // notEmpty is true if the data has arrived for the oldest entry.
    // Bump the oldest pointer when the oldest entry is returned to the
    // client.
    assign oldest_next = oldest + deq_en;

    always_ff @(posedge clk)
    begin
        if (! resetb)
            oldest <= 0;
        else
        begin
            oldest <= oldest_next;
        end
    end


    //
    // Storage where data will be sorted.  Port 0 is used for writes and
    // port 1 for reads.
    //
    qa_drv_prim_dualport_ram#(.N_ENTRIES(N_ENTRIES),
                              .N_DATA_BITS(N_DATA_BITS))
        mem(.clk0(clk),
            .addr0(enqDataIdx),
            .wen0(enqData_en),
            .wdata0(enqData),
            .rdata0(),

            .clk1(clk),
            .addr1(oldest_next),
            .wen1(1'b0),
            .wdata1(N_DATA_BITS'(0)),
            .rdata1(first));


    //
    // Manage the meta-data memory.
    //
    t_META_DATA metaData[0 : N_ENTRIES-1];

    t_META_DATA meta_oldest;
    assign firstMeta = meta_oldest;

    always_ff @(posedge clk)
    begin
        meta_oldest <= metaData[oldest_next];

        // Meta-data is written along with the original request to allocate
        // a slot.
        if (enq_en)
        begin
            metaData[enqIdx] <= enqMeta;
        end
    end


    // Track valid data
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            dataValid <= 1'b0;
        end
        else
        begin
            // Clear on completion
            if (deq_en)
            begin
                dataValid[oldest] <= 1'b0;
            end

            // Set when data arrives
            if (enqData_en)
            begin
                dataValid[enqDataIdx] <= 1'b1;
            end

            assert(! deq_en || notEmpty) else
                $fatal("qa_drv_prim_scoreboard: Can't DEQ when EMPTY!");
        end
    end


    // Track whether the oldest entry's data is valid and should be made
    // available to the client.
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            notEmpty <= 1'b0;
        end
        else
        begin
            notEmpty <= dataValid[oldest_next];
        end
    end

endmodule // qa_dvr_scoreboard
