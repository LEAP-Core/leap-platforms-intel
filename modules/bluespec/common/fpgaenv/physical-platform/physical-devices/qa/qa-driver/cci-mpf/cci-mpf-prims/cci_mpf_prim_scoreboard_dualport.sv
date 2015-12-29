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
// Same as cci_mpf_prim_scoreboard except that the payload and ordered
// output are dual ported.
//

module cci_mpf_prim_scoreboard_dualport
  #(
    parameter N_ENTRIES = 32,
    parameter N_DATA_BITS = 64,
    parameter N_META_BITS = 1,
    // Threshold below which heap asserts "full"
    parameter MIN_FREE_SLOTS = 1
    )
   (
    input  logic clk,
    input  logic reset_n,

    // Add a new entry to the scoreboard.  No payload, just control.
    // The scoreboard returns a handle -- the index where the payload should
    // be written.
    input  logic enq_en,                            // Allocate an entry
    input  logic [N_META_BITS-1 : 0] enqMeta,       // Save meta-data for new entry
    output logic notFull,                           // Is scoreboard full?
    output logic [$clog2(N_ENTRIES)-1 : 0] enqIdx,  // Index of new entry

    // Payload write.  No ready signal.  The scoreboard must always be ready
    // to receive data.
    input  logic enqData_en[0 : 1],                 // Store data for existing entry
    input  logic [$clog2(N_ENTRIES)-1 : 0] enqDataIdx[0 : 1],
    input  logic [N_DATA_BITS-1 : 0] enqData[0 : 1],

    // Ordered output
    input  logic deq_en[0 : 1],                     // Deq oldest entry
    output logic notEmpty[0 : 1],                   // Is oldest entry ready?
    output logic [N_DATA_BITS-1 : 0] first[0 : 1], // Data for oldest entry
    output logic [N_META_BITS-1 : 0] firstMeta[0 : 1] // Meta-data for oldest entry
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
        if (! reset_n)
        begin
            newest <= 0;
        end
        else if (enq_en)
        begin
            newest <= newest + 1;

            assert ((newest + t_IDX'(1)) != oldest) else
                $fatal("cci_mpf_prim_scoreboard_dualport: Can't ENQ when FULL!");
            assert ((N_ENTRIES & (N_ENTRIES - 1)) == 0) else
                $fatal("cci_mpf_prim_scoreboard_dualport: N_ENTRIES must be a power of 2!");
        end
    end


    logic did_deq;
    assign did_deq = deq_en[0] || deq_en[1];


    // notEmpty is true if the data has arrived for the oldest entry.
    // Bump the oldest pointer when the oldest entry is returned to the
    // client.
    assign oldest_next = oldest + did_deq;

    always_ff @(posedge clk)
    begin
        if (! reset_n)
            oldest <= 0;
        else
        begin
            oldest <= oldest_next;
        end
    end


    //
    // Storage where data will be sorted. Dual-ported arriving data shares
    // memory ports with the ordered output data. Arriving data is given
    // priority since it would otherwise be lost.
    //
    t_IDX m_addr[0 : 1];

    cci_mpf_prim_dualport_ram#(.N_ENTRIES(N_ENTRIES),
                              .N_DATA_BITS(N_DATA_BITS))
        mem(.clk0(clk),
            .addr0(m_addr[0]),
            .wen0(enqData_en[0]),
            .wdata0(enqData[0]),
            .rdata0(first[0]),

            .clk1(clk),
            .addr1(m_addr[1]),
            .wen1(enqData_en[1]),
            .wdata1(enqData[1]),
            .rdata1(first[1]));

    // Incoming data is given priority over responses
    assign m_addr[0] = enqData_en[0] ? enqDataIdx[0] : oldest_next;
    assign m_addr[1] = enqData_en[1] ? enqDataIdx[1] : oldest_next;


    //
    // Manage the meta-data memory.
    //
    t_META_DATA metaData[0 : N_ENTRIES-1];

    t_META_DATA meta_oldest;
    assign firstMeta[0] = meta_oldest;
    assign firstMeta[1] = meta_oldest;

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
        if (! reset_n)
        begin
            dataValid <= 1'b0;
        end
        else
        begin
            // Clear on completion. Only one output port can have valid data
            // at a time.
            if (did_deq)
            begin
                dataValid[oldest] <= 1'b0;
            end

            // Set when data arrives
            for (int i = 0; i < 2; i = i + 1)
            begin
                if (enqData_en[i])
                begin
                    dataValid[enqDataIdx[i]] <= 1'b1;
                end
            end

            assert(! (deq_en[0] && deq_en[1])) else
                $fatal("cci_mpf_prim_scoreboard_dualport: Dual deq!");

            assert(! deq_en[0] || notEmpty[0]) else
                $fatal("cci_mpf_prim_scoreboard_dualport: Can't DEQ when EMPTY (0)!");
            assert(! deq_en[1] || notEmpty[1]) else
                $fatal("cci_mpf_prim_scoreboard_dualport: Can't DEQ when EMPTY (1)!");
        end
    end


    // Track whether the oldest entry's data is valid and should be made
    // available to the client.
    always_ff @(posedge clk)
    begin
        if (! reset_n)
        begin
            notEmpty[0] <= 1'b0;
            notEmpty[1] <= 1'b0;
        end
        else
        begin
            //
            // Only one of the two output ports will assert notEmpty in a
            // given cycle. The one that does depends on which internal
            // RAM read port is available.
            //
            // Favor port 1.
            //
            notEmpty[0] <= dataValid[oldest_next] && ! enqData_en[0] &&
                           enqData_en[1];

            notEmpty[1] <= dataValid[oldest_next] && ! enqData_en[1];
        end
    end

endmodule // cci_mpf_prim_scoreboard_dualport

