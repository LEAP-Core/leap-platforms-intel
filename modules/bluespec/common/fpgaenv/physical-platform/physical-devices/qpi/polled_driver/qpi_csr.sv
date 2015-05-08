`include "qpi.vh"

module qpi_csr
     (
          input logic clk,
          input logic resetb,
          input rx_c0_t rx0,
   
          output  afu_csr_t           csr

      );

      always_comb begin
         if (rx0.cfgvalid)
           $display("SETTING CONFIG 0x%h 0x%h", {rx0.header[11:0], 2'b0}, rx0.data[31:0]);
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_DSM_BASEL) begin
                  csr.afu_dsm_base[31:0] <= rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (~resetb) begin
                  csr.afu_dsm_base_valid <= 0;

               end else if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_DSM_BASEL) begin
                  csr.afu_dsm_base_valid <= 1;

               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_DSM_BASEH) begin
                  csr.afu_dsm_base[63:32] <= rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_CNTXT_BASEL) begin
                  csr.afu_cntxt_base[31:0] <= rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (~resetb) begin
                  csr.afu_cntxt_base_valid <= 0;

               end else if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_CNTXT_BASEL) begin
                  csr.afu_cntxt_base_valid <= 1;

               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_CNTXT_BASEH) begin
                  csr.afu_cntxt_base[63:32] <= rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (~resetb) begin
                  csr.afu_en <= 0;
               end
               else if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_EN) begin
                  csr.afu_en <= rx0.data[0];

               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_READ_FRAME_BASEL) begin
                  csr.afu_read_frame[31:0] <= rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_READ_FRAME_BASEH) begin
                  csr.afu_read_frame[63:32] <= rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_WRITE_FRAME_BASEL) begin
                  csr.afu_write_frame[31:0] <= rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (rx0.cfgvalid && {rx0.header[11:0], 2'b0} == CSR_AFU_WRITE_FRAME_BASEH) begin
                  csr.afu_write_frame[63:32] <= rx0.data[31:0];
               end
      end
   
endmodule
