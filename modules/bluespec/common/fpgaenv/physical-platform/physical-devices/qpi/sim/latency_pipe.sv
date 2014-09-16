/*
 * Generic register block
 * A D-flip flop implementation
 */
module register
  #(
    parameter REG_WIDTH = 1
    )
   (
    input logic 		 clk,
    input logic 		 rst,
    input logic [REG_WIDTH-1:0]  d,
    output logic [REG_WIDTH-1:0] q
    );


   // DFF behaviour
   always @( posedge clk or posedge rst ) begin
      if (rst)
	q <= 0;
      else
	q <= d;
   end

endmodule


/*
 * latency_pipe : A generic N-stage, W-width pipeline that delays
 * input by a known number of clocks
 */
module latency_pipe
  #(
    parameter NUM_DELAY = 5,
    parameter PIPE_WIDTH = 1
    )
   (
    input logic 		  clk,
    input logic 		  rst,
    input logic [PIPE_WIDTH-1:0]  pipe_in,
    output logic [PIPE_WIDTH-1:0] pipe_out
    );

   logic [PIPE_WIDTH-1:0] 	 pipe_in_tmp [0:NUM_DELAY-1];
   logic [PIPE_WIDTH-1:0] 	 pipe_out_tmp [0:NUM_DELAY-1];


   // Register stages (instantiated here, not connected)
   genvar 		    ii;
   generate
      for(ii = 0; ii < NUM_DELAY; ii = ii + 1) begin
	 register
	       #(
		 .REG_WIDTH (PIPE_WIDTH)
		 )
	 reg_i
	       (
		.clk (clk),
		.rst (rst),
		.d   (pipe_in_tmp[ii]),
		.q   (pipe_out_tmp[ii])
		);
      end
   endgenerate

   // Pipeline stages connected here
   genvar 		    jj;
   generate
      for(jj = 1; jj < NUM_DELAY; jj = jj + 1) begin
	 assign pipe_in_tmp[jj] = pipe_out_tmp[jj - 1];
      end
   endgenerate

   assign pipe_in_tmp[0] = pipe_in;
   assign pipe_out = pipe_out_tmp[NUM_DELAY-1];

endmodule
