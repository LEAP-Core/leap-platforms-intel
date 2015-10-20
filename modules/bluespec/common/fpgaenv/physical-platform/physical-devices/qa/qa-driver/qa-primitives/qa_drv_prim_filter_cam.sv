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


module qa_drv_prim_filter_cam
  #(
    // Number of individual buckets in the filter
    parameter N_BUCKETS = 16,
     // Size of each bucket in the counting filter
    parameter BITS_PER_BUCKET = 4,
    // Number of clients attempting to test an entry
    parameter N_TEST_CLIENTS = 1,
    // Number of clients attempting to remove an entry
    parameter N_REMOVE_CLIENTS = 1,
    // Include values inserted in the current cycle in the test this cycle?
    // Be careful here, since enabling the bypass can cause a dependence
    // loop. The bypass is useful if there is a pipeline stage between
    // test and insertion.
    parameter BYPASS_INSERT_TO_TEST = 0
    )
   (
    input  logic clk,
    input  logic resetb,

    // Test values against the set of values stored in the CAM.
    input  logic [0 : N_TEST_CLIENTS-1][BITS_PER_BUCKET-1 : 0] test_value,
    input  logic [0 : N_TEST_CLIENTS-1]                 test_en,
    output logic [0 : N_TEST_CLIENTS-1]                 test_notPresent,
    // Mirrors test_notPresent but one cycle delayed. Internally this gives
    // the logic more time to implement the CAM and the computation is split
    // across the cycles.
    output logic [0 : N_TEST_CLIENTS-1]                 test_notPresent_reg,

    // Insert one value into the CAM in a specific slot. Slots are managed
    // outside this module.
    input  logic [$clog2(N_BUCKETS)-1 : 0]              insert_idx,
    input  logic [BITS_PER_BUCKET-1 : 0]                insert_value,
    input  logic                                        insert_en,

    // Remove (invalidate) entries from the CAM.
    input  logic [0 : N_REMOVE_CLIENTS-1][$clog2(N_BUCKETS)-1 : 0] remove_idx,
    input  logic [0 : N_REMOVE_CLIENTS-1]                          remove_en
    );
     
    // Storage for the values
    logic [0 : N_BUCKETS-1][BITS_PER_BUCKET-1 : 0] values;
    logic [0 : N_BUCKETS-1] valid;

    // Test insert and protect
    logic [0 : N_TEST_CLIENTS-1] insert_match;

    genvar g;
    generate
        if (BYPASS_INSERT_TO_TEST == 0)
        begin
            // If not bypassing then claim it never matches.
            assign insert_match = N_BUCKETS'(0);
        end
        else
        begin
            // Bypassing: compare insert and test values.
            for (g = 0; g < N_TEST_CLIENTS; g = g + 1)
            begin : im
                assign insert_match[g] = (insert_value == test_value[g]);
            end
        end
    endgenerate

    logic [0 : N_TEST_CLIENTS-1][0 : N_BUCKETS-1] test_match;

    always_comb
    begin
        //
        // Compare test input against all values stored in the filter.
        //
        for (int c = 0; c < N_TEST_CLIENTS; c = c + 1)
        begin
            // Construct a bit vector that is the result of comparing each
            // entry to the target.
            for (int b = 0; b < N_BUCKETS; b = b + 1)
            begin
                test_match[c][b] = (values[b] == test_value[c]);
            end

            // Is the value present in the CAM?
            test_notPresent[c] = (! test_en[c] ||
                                  // Does any valid entry match?
                                  (! (|(valid & test_match[c])) &&
                                   // Did the inserted entry match?
                                   (! insert_en || ! insert_match[c])));
        end
    end


    // Registered equivalent of the combinational logic, producing the
    // test_notPresent_delayed result. This is the same result as
    // test_notPresent returned the previous cycle with computation spread
    // across the two cycles to relax timing.
    logic [0 : N_TEST_CLIENTS-1] reg_test_en;
    logic [0 : N_TEST_CLIENTS-1][0 : N_BUCKETS-1] reg_test_match;
    logic [0 : N_TEST_CLIENTS-1] reg_insert_match;

    generate
        for (g = 0; g < N_TEST_CLIENTS; g = g + 1)
        begin : registered
            assign test_notPresent_reg[g] =
                (! reg_test_en[g] ||
                 // Not present if no matches
                 (! (| reg_test_match[g]) && ! reg_insert_match[g]));
        end
    endgenerate

    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            reg_test_en <= 0;
        end
        else
        begin
            for (int c = 0; c < N_TEST_CLIENTS; c = c + 1)
            begin
                reg_test_en[c] <= test_en[c];
                reg_test_match[c] <= valid & test_match[c];
                reg_insert_match[c] = insert_en && insert_match[c];
            end
        end
    end

      
    //
    // Insert new entries
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            valid <= N_BUCKETS'(0);
        end
        else
        begin
            // Insert new entry
            if (insert_en)
            begin
                values[insert_idx] <= insert_value;
                valid[insert_idx] <= 1'b1;
            end

            // Remove old entries
            for (int c = 0; c < N_REMOVE_CLIENTS; c = c + 1)
            begin
                if (remove_en[c])
                begin
                    valid[remove_idx[c]] <= 1'b0;
                end
            end
        end
    end

endmodule // qa_drv_prim_filter_cam

