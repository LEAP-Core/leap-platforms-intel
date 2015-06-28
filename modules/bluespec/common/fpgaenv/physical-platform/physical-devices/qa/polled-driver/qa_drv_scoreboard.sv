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
// Scoreboard that behaves like a FIFO that allows out of order arrival of
// the payload.  Since the intended use of the scoreboard is to reorder memory
// read responses, there is little point in enabling full bandwidth read and
// write from the scoreboard.  Instead, the internal memory is half the
// width of the data and either both write ports or both read ports are
// used to spread data over two entries.
//
// The scoreboard combines two pieces of data with each entry:
// meta-data that is supplied at the time an index is allocated and the
// late-arriving data.  Both are returned together through first and first_meta.
//
//
//
module qa_drv_scoreboard
  #(parameter N_ENTRIES = 32,
              N_DATA_BITS = 64,
              N_META_BITS = 1)
    (input  logic clk,
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

    localparam N_NARROW_DATA_BITS = N_DATA_BITS / 2;

    typedef logic [N_DATA_BITS-1 : 0] t_DATA;
    typedef logic [N_NARROW_DATA_BITS-1 : 0] t_NARROW_DATA;
    typedef logic [N_META_BITS-1 : 0] t_META_DATA;
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_IDX;

    //
    // Output is routed through a FIFO to relax timing paths to the internal
    // block RAM.  A FIFO1 is sufficient since the internal logic already
    // prevents read and write in the same cycle.
    //

    typedef struct packed
    {
        t_DATA data;
        t_META_DATA meta;
    }
    t_OUTPUT_DATA;

    // Container for data entering the output FIFO
    t_OUTPUT_DATA out_fifo_enq_data;

    // Container for data leaving the output FIFO, bound for the client
    t_OUTPUT_DATA out_fifo_deq_data;
    assign first = out_fifo_deq_data.data;
    assign firstMeta = out_fifo_deq_data.meta;

    logic out_fifo_enq_req;
    logic out_fifo_notFull;
    logic out_fifo_enq_en;
    assign out_fifo_enq_en = out_fifo_enq_req && out_fifo_notFull;

    qa_drv_fifo1#(.N_DATA_BITS($bits(t_OUTPUT_DATA)))
        fifo_out(.clk, .resetb,
                 .enq_data(out_fifo_enq_data),
                 .enq_en(out_fifo_enq_en),
                 .notFull(out_fifo_notFull),
                 .first(out_fifo_deq_data),
                 .deq_en,
                 .notEmpty);


    // Scoreboard is empty when oldest == newest and full when
    // newest + 1 == oldest.
    t_IDX newest;
    t_IDX oldest;
    t_IDX oldest_next;

    // Track data arrival
    reg [N_ENTRIES-1 : 0] dataValid;
    logic [N_ENTRIES-1 : 0] dataValid_next;

    assign notFull = ((newest + t_IDX'(1)) != oldest);

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

            assert (notFull) else
                $fatal("qa_drv_scoreboard: Can't ENQ when FULL!");
        end
    end


    // notEmpty is true if the data has arrived for the oldest entry.
    // Bump the oldest pointer when the oldest entry is moved to the
    // output FIFO.
    assign oldest_next = oldest + out_fifo_enq_en;

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
    // Manage the data memory.
    //
    // Writes have priority since the incoming data is latency sensitive
    // and must be stored.  Because the memory is half the width of
    // incoming data both memory ports are used to complete a write.
    //
    t_NARROW_DATA data[0 : (2*N_ENTRIES)-1];

    t_NARROW_DATA enqData_pair[0:1];
    assign enqData_pair[0] = enqData[N_NARROW_DATA_BITS-1 : 0];
    assign enqData_pair[1] = enqData[N_DATA_BITS-1 : N_NARROW_DATA_BITS];

    t_NARROW_DATA first_pair[0:1];
    assign out_fifo_enq_data.data = {first_pair[1], first_pair[0]};

    t_IDX ram_addr;
    assign ram_addr = enqData_en ? enqDataIdx : oldest_next;

    //
    // True dual port Block RAM, based on Altera template.
    //
    //   Address of read and write must be identical within a port or it
    //   won't be inferred as a block RAM.
    //

    // Port A
    always @(posedge clk)
    begin
        if (enqData_en)
        begin
            data[{ram_addr, 1'b0}] <= enqData_pair[0];
            // Altera includes this bypass in the sample dual write port memory.
            first_pair[0] <= enqData_pair[0];
        end
        else
        begin
            first_pair[0] <= data[{ram_addr, 1'b0}];
        end
    end

    // Port B
    always @(posedge clk)
    begin
        if (enqData_en)
        begin
            data[{ram_addr, 1'b1}] <= enqData_pair[1];
            // Altera includes this bypass in the sample dual write port memory.
            first_pair[1] <= enqData_pair[1];
        end
        else
        begin
            first_pair[1] <= data[{ram_addr, 1'b1}];
        end
    end

    //
    // Manage the meta-data memory.
    //
    t_META_DATA metaData[0 : N_ENTRIES-1];

    t_META_DATA meta_oldest;
    assign out_fifo_enq_data.meta = meta_oldest;

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
            dataValid <= dataValid_next;
        end
    end

    always_comb
    begin
        dataValid_next = dataValid;

        // Clear on move to output FIFO
        if (out_fifo_enq_en)
        begin
            dataValid_next[oldest] = 1'b0;
        end

        // Set when data arrives
        if (enqData_en)
        begin
            dataValid_next[enqDataIdx] = 1'b1;
        end
    end


    // Track whether the oldest entry's data is valid and should be moved
    // to the output FIFO.
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            out_fifo_enq_req <= 1'b0;
        end
        else
        begin
            //
            // Collect data only on cycles where access to the memory's
            // read port is available.
            //
            // A scoreboard BRAM write uses both ports since the
            // memory is half the width of the incoming data.  Memory
            // responses are latency sensitive and there is no other buffer
            // available, so writes have priority over reads.
            //
            out_fifo_enq_req <= dataValid[oldest_next] &&
                                // Block RAM is available
                                ! enqData_en;
        end
    end

endmodule // qa_dvr_scoreboard
