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
//   A FIFO with two storage elements supporting full pipelining.
//

module qa_drv_prim_fifo2
  #(parameter N_DATA_BITS = 32)
    (input  logic clk,
     input  logic resetb,

     input  logic [N_DATA_BITS-1 : 0] enq_data,
     input  logic                     enq_en,
     output logic                     notFull,

     output logic [N_DATA_BITS-1 : 0] first,
     input  logic                     deq_en,
     output logic                     notEmpty
     );
     
    logic [N_DATA_BITS-1 : 0] data[0:1] /* synthesis ramstyle = "logic" */;
    logic [1:0] valid_cnt;
    logic [1:0] valid_cnt_next;
    logic wr_idx;
    logic rd_idx;

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
            wr_idx <= ! wr_idx;

            assert (notFull) else
                $fatal("qa_drv_fifo: ENQ to full FIFO!");
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
            rd_idx <= ! rd_idx;

            assert (notEmpty) else
                $fatal("qa_drv_fifo: DEQ from empty FIFO!");
        end
    end

    // Update count of live values
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            valid_cnt <= 2'b0;
            notFull <= 1'b1;
            notEmpty <= 1'b0;
        end
        else
        begin
            valid_cnt <= valid_cnt_next;
            notFull <= (valid_cnt_next != 2);
            notEmpty <= (valid_cnt_next != 0);
        end
    end

    always_comb
    begin
        valid_cnt_next = valid_cnt;

        if (deq_en && ! enq_en)
        begin
            valid_cnt_next = valid_cnt_next - 2'b1;
        end
        else if (enq_en && ! deq_en)
        begin
            valid_cnt_next = valid_cnt_next + 2'b1;
        end
    end

endmodule // qa_drv_fifo1
