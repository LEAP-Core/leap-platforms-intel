// -------------------------------------------------------------------
// FIFO module (Verilog)
// Author : Rahul R Sharma
//          Intel Corporation
// Details : Built on circular buffer method
// -------------------------------------------------------------------

// Top module
module fifo
  #(
    parameter DATA_WIDTH        = 32,  // Data width
    parameter DEPTH             = 4,   // Depth is 2^(this number)
    parameter FALL_THRU_NOT_REG = 1,   // FWFT FIFO vs Reg FIFO
    parameter SHUFFLE_DEGREE    = 0    // Shuffle not used, !!! DO NOT EDIT !!!
    )
   (
    input wire clk,
    input wire rst,
    input wire [DATA_WIDTH-1:0] din,
    input wire read,
    input wire write,
    output reg [DATA_WIDTH-1:0] dout,
    output wire empty,
    output wire almostfull
    );

   // Calculate max count
   parameter MAX_COUNT  = (1<<DEPTH);   // Calculate maximum depth

   // Head tail and count
   reg [DEPTH-1:0] tail;
   reg [DEPTH-1:0] head;
   reg [DEPTH-1:0] count;
   reg 		   full;

   // temp variable
   int 		   iter;

   // FIFO memory
   reg [DATA_WIDTH-1:0] fifo_mem[MAX_COUNT-1:0];

   wire 		rd_valid = ((read == 1) && (empty == 0));
   wire 		wr_valid = ((write == 1) && (full == 0));


   // Setting dout
   generate
      if (FALL_THRU_NOT_REG == 1) begin
         always @(posedge clk) begin
            assign dout = fifo_mem[tail];
         end
      end
      else begin
         always @(posedge clk) begin
            if (read == 1) begin
               dout = fifo_mem[tail];
            end
            else begin
               dout = 0;
            end
         end
      end
   endgenerate

   // setting din
   always @(posedge clk)
      if(rst == 0) begin
         if((write == 1) && (full == 0)) begin
            fifo_mem[head] = din;
         end
      end
      else begin
         fifo_mem[head] = 0;
      end

   // Initially memory is reset
   initial
      begin
         for(iter = 0; iter < MAX_COUNT; iter = iter + 1)
            begin
               fifo_mem[iter] = 0;
            end
      end

   // update head
   always @(posedge clk) begin
      if(rst) begin
         head <= 0;
      end
      else begin
         if(wr_valid) begin
            head <= head + 1;
         end
         else begin
            head <= head;
         end
      end // else: !if(rst)
   end


   // update tail
   always @(posedge clk) begin
      if(rst) begin
         tail <= 0;
      end
      else begin
         if(rd_valid) begin
            tail <= tail + 1;
         end
         else begin
            tail <= tail;
         end
      end
   end

   // Count elements in FIFO
   always @(posedge clk) begin
      if(rst) begin
         count <= 0;
      end
      else begin
         case({rd_valid, wr_valid})
            2'b00 :
               count <= count;
            2'b01 :
               count <= count + 1;
            2'b10 :
               count <= count - 1;
            2'b11 :
               count <= count;
         endcase // case ({read, write})
      end // else: !if(rst)
   end // always @ (posedge clk)

   assign empty = (count == 0)   ;
   assign full = (count == MAX_COUNT-1);
   assign almostfull = (count >= MAX_COUNT - 5);

endmodule // fifo


