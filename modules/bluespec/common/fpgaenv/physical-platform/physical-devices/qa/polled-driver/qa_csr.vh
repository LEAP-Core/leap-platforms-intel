// Code generated by afu_csr_gen


`ifndef QA_CSR_VH
`define QA_CSR_VH

localparam CSR_AFU_DSM_BASEL          = 13'h1a00;
localparam CSR_AFU_DSM_BASEH          = 13'h1a04;
localparam CSR_AFU_CNTXT_BASEL        = 13'h1a08;
localparam CSR_AFU_CNTXT_BASEH        = 13'h1a0c;
localparam CSR_AFU_EN                 = 13'h1a10;
localparam CSR_AFU_READ_FRAME_BASEL   = 13'h1a18;
localparam CSR_AFU_READ_FRAME_BASEH   = 13'h1a1c;
localparam CSR_AFU_WRITE_FRAME_BASEL  = 13'h1a20;
localparam CSR_AFU_WRITE_FRAME_BASEH  = 13'h1a24;

typedef struct
                {
                   logic afu_dsm_base_valid;
                   logic [63:0] afu_dsm_base;
                   logic        afu_cntxt_base_valid;
                   logic [63:0] afu_cntxt_base;
                   logic        afu_en;
                   logic [63:0] afu_write_frame;
                   logic [63:0] afu_read_frame;
                } afu_csr_t;

`endif //  `ifndef QA_CSR_VH

