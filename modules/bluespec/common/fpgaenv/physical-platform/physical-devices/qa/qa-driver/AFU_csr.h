//
// CSR addresses must match qa_drv_csr_types.sv exactly!
//

#define CSR_AFU_DSM_BASE        0x1a00
#define CSR_AFU_CNTXT_BASE      0x1a08
#define CSR_AFU_EN              0x1a10

// We use 64-bit writes, automatically broken down by the software into a
// pair of writes.  Hence the difference in names in the hardware version.
#define CSR_READ_FRAME          0x1a18
#define CSR_WRITE_FRAME         0x1a20

#define CSR_AFU_TRIGGER_DEBUG   0x1a28
#define CSR_AFU_ENABLE_TEST     0x1a2c
#define CSR_AFU_SREG_READ       0x1a30


//
// System CSRs
//
#define CSR_CIPUCTL             0x280
