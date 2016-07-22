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
// Decode filter allows clients to add entries to the filter by index.
// Entries are set as single bits in a RAM.  An entry is present when
// the corresponding bit is set.
//

module cci_mpf_prim_filter_decode
  #(
    // Number of individual entries in the filter
    parameter N_ENTRIES = 16,
    // Number of clients attempting to test an entry
    parameter N_TEST_CLIENTS = 1
    )
   (
    input  logic clk,
    input  logic reset,
    output logic rdy,

    // Test values against the set of values stored in the CAM.
    input  logic [0 : N_TEST_CLIENTS-1][$clog2(N_ENTRIES)-1 : 0] test_value,
    input  logic [0 : N_TEST_CLIENTS-1] test_en,
    output logic [0 : N_TEST_CLIENTS-1] T3_test_notPresent,
    // The tag is a value that must be passed to insert_tag and
    // remove_tag below in order to update test_value in the filter.
    // These arguments are needed to save block RAM resources.  The
    // filter is implemented as the XOR of a pair of block RAMs, working
    // around the limited number of block RAM read and write ports.
    // Passing tags around reduces the number of RAMs required, using the
    // reads required for tests to look up the memory state as a side effect.
    output logic [0 : N_TEST_CLIENTS-1] T3_test_insert_tag,

    // Insert one value into the filter in a specific slot. Slots are managed
    // outside this module.
    input  logic [$clog2(N_ENTRIES)-1 : 0] insert_value,
    // Pass the corresponding lookup value from T3_test_insert_tag above
    input  logic insert_tag,
    input  logic insert_en,

    // Remove (invalidate) entries from the filter.
    input  logic [$clog2(N_ENTRIES)-1 : 0] remove_value,
    // Pass the corresponding lookup value from T3_test_insert_tag above
    input  logic remove_tag,
    input  logic remove_en
    );
     
    typedef logic [$clog2(N_ENTRIES)-1 : 0] t_idx;

    logic [0 : N_TEST_CLIENTS-1] test_state_A;
    logic [0 : N_TEST_CLIENTS-1] test_state_B;

    logic [0 : N_TEST_CLIENTS-1] init_done;
    assign rdy = init_done[0];

    logic test_en_q[0 : N_TEST_CLIENTS-1];
    logic test_en_qq[0 : N_TEST_CLIENTS-1];

    genvar p;
    generate
        for (p = 0; p < N_TEST_CLIENTS; p = p + 1)
        begin : r
            // An entry is not present if the values in memA and memB match
            always_ff @(posedge clk)
            begin
                T3_test_notPresent[p] <= 1'b0;
                if (test_en_qq[p])
                begin
                    T3_test_notPresent[p] <= (test_state_A[p] == test_state_B[p]);
                end

                T3_test_insert_tag[p] <= ~ test_state_A[p];

                test_en_q[p] <= test_en[p];
                test_en_qq[p] <= test_en_q[p];
            end

            // The write port in memA is used for insert
            cci_mpf_prim_ram_simple_init
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(1),
                .N_OUTPUT_REG_STAGES(1)
                )
              memA
               (
                .clk,
                .reset,
                .rdy(init_done[p]),

                .wen(insert_en),
                .waddr(insert_value),
                .wdata(insert_tag),

                .raddr(test_value[p]),
                .rdata(test_state_A[p])
                );

            // The write port in memB is used for remove
            cci_mpf_prim_ram_simple_init
              #(
                .N_ENTRIES(N_ENTRIES),
                .N_DATA_BITS(1),
                .N_OUTPUT_REG_STAGES(1)
                )
              memB
               (
                .clk,
                .reset,
                .rdy(),

                .wen(remove_en),
                .waddr(remove_value),
                .wdata(remove_tag),

                .raddr(test_value[p]),
                .rdata(test_state_B[p])
                );
        end
    endgenerate

endmodule // cci_mpf_prim_filter_decode


