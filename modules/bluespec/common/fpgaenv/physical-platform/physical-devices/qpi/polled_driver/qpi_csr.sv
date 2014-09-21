`include "qpi.vh"

module afu_csr
     (
          input logic clk,
          input logic resetb,
          cci_bus_t cci_bus,
          afu_bus_t afu_bus
      );


      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_DSM_BASEL) begin
                  afu_bus.csr.afu_dsm_base[31:0] <= cci_bus.rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (~resetb) begin
                  afu_bus.csr.afu_dsm_base_valid <= 0;

               end else if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_DSM_BASEL) begin
                  afu_bus.csr.afu_dsm_base_valid <= 1;

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_DSM_BASEH) begin
                  afu_bus.csr.afu_dsm_base[63:32] <= cci_bus.rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_CNTXT_BASEL) begin
                  afu_bus.csr.afu_cntxt_base[31:0] <= cci_bus.rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (~resetb) begin
                  afu_bus.csr.afu_cntxt_base_valid <= 0;

               end else if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_CNTXT_BASEL) begin
                  afu_bus.csr.afu_cntxt_base_valid <= 1;

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_CNTXT_BASEH) begin
                  afu_bus.csr.afu_cntxt_base[63:32] <= cci_bus.rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_AFU_EN) begin
                  afu_bus.csr.afu_en <= cci_bus.rx0.data[0];

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_READ_FRAME_BASEL) begin
                  afu_bus.csr.afu_read_frame[31:0] <= cci_bus.rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_READ_FRAME_BASEH) begin
                  afu_bus.csr.afu_read_frame[63:32] <= cci_bus.rx0.data[31:0];

               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_WRITE_FRAME_BASEL) begin
                  afu_bus.csr.afu_write_frame[31:0] <= cci_bus.rx0.data[31:0];
               end
      end

      always_ff @(posedge clk) begin
               if (cci_bus.rx0.cfgvalid && {cci_bus.rx0.header[11:0], 2'b0} == ADDR_WRITE_FRAME_BASEH) begin
                  afu_bus.csr.afu_write_frame[63:32] <= cci_bus.rx0.data[31:0];

               end
      end
   
endmodule   