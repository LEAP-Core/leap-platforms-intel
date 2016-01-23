//
// CSR addresses must match qa_drv_csr_types.sv exactly!
//

#define CSR_AFU_DSM_BASE        0x1a00
#define CSR_AFU_CNTXT_BASE      0x1a08
#define CSR_AFU_SREG_READ       0x1a10

// Page table base for qa_shim_tlb_simple (64 bits)
#define CSR_AFU_PAGE_TABLE_BASE 0x1a80

// MMIO read compatibility for CCI-S.  Writes here are treated
// as a CSR read request.
#define CSR_AFU_MMIO_READ_COMPAT 0x1a14

// The host channels driver manages its own CSR space starting at a
// base address passed to the driver when it is instantiated.
#define CSR_HC_BASE_ADDR        0x1a80

//
// System CSRs
//
#define CSR_CIPUCTL             0x280
