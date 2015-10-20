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


module qa_drv_prim_filter_counting
  #(
    // Number of individual buckets in the filter
    parameter N_BUCKETS = 16,
    // Size of each bucket in the counting filter
    parameter BITS_PER_BUCKET = 4,
    // Number of clients attempting to test an entry
    parameter N_TEST_CLIENTS = 1,
    // Number of clients attempting to insert an entry
    parameter N_INSERT_CLIENTS = 1,
    // Number of clients attempting to remove an entry
    parameter N_REMOVE_CLIENTS = 1
    )
   (
    input  logic clk,
    input  logic resetb,

    // Test a bucket.  The test logic is combinational.  Outputs are available
    // in the same cycle as the request.
    input  logic [0 : N_TEST_CLIENTS-1][$clog2(N_BUCKETS)-1 : 0]   test_req,
    // Will counter overflow if incremented?
    output logic [0 : N_TEST_CLIENTS-1]                            test_notFull,
    output logic [0 : N_TEST_CLIENTS-1]                            test_isZero,

    input  logic [0 : N_INSERT_CLIENTS-1][$clog2(N_BUCKETS)-1 : 0] insert,
    input  logic [0 : N_INSERT_CLIENTS-1]                          insert_en,

    input  logic [0 : N_REMOVE_CLIENTS-1][$clog2(N_BUCKETS)-1 : 0] remove,
    input  logic [0 : N_REMOVE_CLIENTS-1]                          remove_en
    );
     
    // Storage for the counters
    logic [0 : N_BUCKETS-1][BITS_PER_BUCKET-1 : 0] counters;


    // ====================================================================
    //
    // Test logic
    //
    // ====================================================================

    genvar p;
    generate
        for (p = 0; p < N_TEST_CLIENTS; p = p + 1)
        begin : test
            // Technically, notFull should be 1 if there are at least
            // N_INSERT_CLIENTS entries remaining in the bucket. To avoid
            // an add we instead simply require that the high bit be 0,
            // trading storage for time.
            assign test_notFull[p] = (! counters[test_req[p]][BITS_PER_BUCKET-1]);

            assign test_isZero[p] = (counters[test_req[p]] == BITS_PER_BUCKET'(0));
        end
    endgenerate


    // ====================================================================
    //
    // Update logic
    //
    // ====================================================================

    //
    // Each bucket builds its own CAM against request ports
    //
    logic [0 : N_BUCKETS-1][$clog2(N_INSERT_CLIENTS+1)-1 : 0] delta_up;
    logic [0 : N_BUCKETS-1][$clog2(N_REMOVE_CLIENTS+1)-1 : 0] delta_down;

    always_comb
    begin
        for (int c = 0; c < N_BUCKETS; c = c + 1)
        begin
            delta_up[c] = 0;
            delta_down[c] = 0;

            // For each insert port
            for (int i = 0; i < N_INSERT_CLIENTS; i = i + 1)
            begin
                // Increment if insert port index matches and is enabled
                delta_up[c] =
                     delta_up[c] +
                     $bits(delta_up[c])'((insert[i] == c) && insert_en[i]);
            end

            // For each insert port
            for (int i = 0; i < N_REMOVE_CLIENTS; i = i + 1)
            begin
                // Decrement for remove ports
                delta_down[c] =
                     delta_down[c] +
                     $bits(delta_up[c])'((remove[i] == c) && remove_en[i]);
            end
        end
    end


    //
    // Update counters
    //
    genvar b;
    generate
        for (b = 0; b < N_BUCKETS; b = b + 1)
        begin : update
            always_ff @(posedge clk)
            begin
                if (! resetb)
                begin
                    counters[b] <= BITS_PER_BUCKET'(0);
                end
                else
                begin
                    counters[b] <= counters[b] +
                                   BITS_PER_BUCKET'(delta_up[b]) -
                                   BITS_PER_BUCKET'(delta_down[b]);
               end
            end
        end
    endgenerate
endmodule // qa_drv_prim_filter_counting
