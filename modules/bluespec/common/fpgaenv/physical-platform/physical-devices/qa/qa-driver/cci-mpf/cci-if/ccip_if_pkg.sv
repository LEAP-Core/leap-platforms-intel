// Date: 11/4/2015
// Compliant with CCI-P spec v0.6
package ccip_if_pkg;
//=====================================================================
// CCI-P interface defines
//=====================================================================
parameter CCIP_VERSION_NUMBER    = 12'h060;

parameter CCIP_CLADDR_WIDTH      = 42;
parameter CCIP_CLDATA_WIDTH      = 512;

parameter CCIP_MMIOADDR_WIDTH    = 16;
parameter CCIP_MMIODATA_WIDTH    = 64;
parameter CCIP_TID_WIDTH         = 9;

parameter CCIP_MDATA_WIDTH       = 16;

// Number of requests that can be accepted after almost full is asserted.
parameter CCIP_ALMOST_FULL_THRESHOLD = 4;


// Base types
//----------------------------------------------------------------------
typedef logic [CCIP_CLADDR_WIDTH-1:0] t_ccip_claddr;
typedef logic [CCIP_CLDATA_WIDTH-1:0] t_ccip_cldata;

typedef logic [CCIP_MMIOADDR_WIDTH-1:0] t_ccip_mmioaddr;
typedef logic [CCIP_MMIODATA_WIDTH-1:0] t_ccip_mmiodata;
typedef logic [CCIP_TID_WIDTH-1:0] t_ccip_tid;

typedef logic [CCIP_MDATA_WIDTH-1:0] t_ccip_mdata;

// Request Type  Encodings
//----------------------------------------------------------------------
typedef enum logic [3:0] {
    eREQ_WRLINE_I  = 4'h1,      // Memory Write with FPGA Cache Hint=Invalid
    eREQ_WRLINE_M  = 4'h2,      // Memory Write with FPGA Cache Hint=Modified
    eREQ_WRFENCE   = 4'h5,      // Memory Write Fence
    eREQ_RDLINE_S  = 4'h4,      // Memory Read with FPGA Cache Hint=Shared
    eREQ_RDLINE_I  = 4'h6,      // Memory Read with FPGA Cache Hint=Invalid
    eREQ_INTR      = 4'h8       // Interrupt the CPU ** NOT SUPPORTED CURRENTLY **
} t_ccip_req;
// Response Type  Encodings
//----------------------------------------------------------------------
typedef enum logic [3:0] {
    eRSP_WRLINE = 4'h1,         // Memory Write
    eRSP_RDLINE = 4'h4,         // Memory Read
    eRSP_INTR   = 4'h8,         // Interrupt delivered to the CPU ** NOT SUPPORTED CURRENTLY **
    eRSP_UMSG   = 4'hF          // UMsg received ** NOT SUPPORTED CURRENTLY **
} t_ccip_rsp;
//
// Virtual Channel Select
//----------------------------------------------------------------------
typedef enum logic [1:0] {
    eVC_VA  = 2'b00,            // Auto channel -- least busy channel selected
    eVC_VL0 = 2'b01,            // Cached channel
    eVC_VH0 = 2'b10,            // PCIe channel 0
    eVC_VH1 = 2'b11             // PCIe channel 1
} t_ccip_vc;
//
// Cache line number for multi-line requests and responses
//----------------------------------------------------------------------
typedef logic [1:0] t_ccip_cl_num;
//
// Structures for Request and Response headers
//----------------------------------------------------------------------
typedef struct packed {
    t_ccip_vc       vc_sel;
    logic           sop;
    logic           rsvd1;
`ifdef CCIP_IF_V0_1
    t_ccip_cl_num   cl_num;
`else
    logic [1:0]     length;
`endif
    t_ccip_req      req_type;
    logic [5:0]     rsvd0;
    t_ccip_claddr   address;
    t_ccip_mdata    mdata;
} t_ccip_ReqMemHdr;
parameter CCIP_TX_MEMHDR_WIDTH = $bits(t_ccip_ReqMemHdr);

typedef struct packed {
    t_ccip_vc       vc_used;
    logic           poison;
    logic           hit_miss;
    logic           fmt;
    logic           rsvd0;
    t_ccip_cl_num   cl_num;
    t_ccip_rsp      resp_type;
    t_ccip_mdata    mdata;
} t_ccip_RspMemHdr;
parameter CCIP_RX_MEMHDR_WIDTH = $bits(t_ccip_RspMemHdr);

typedef struct packed {
    t_ccip_mmioaddr address;    // 4B aligned Mmio address
    logic [1:0]     length;     // 2'b00- 4B, 2'b01- 8B, 2'b10- 64B
    logic           poison;
    t_ccip_tid      tid;
} t_ccip_Req_MmioHdr;
parameter CCIP_RX_MMIOHDR_WIDTH = $bits(t_ccip_Req_MmioHdr);

typedef struct packed {
    t_ccip_tid      tid;        // Returnd back from Request header
} t_ccip_Rsp_MmioHdr;
parameter CCIP_TX_MMIOHDR_WIDTH = $bits(t_ccip_Rsp_MmioHdr);

//------------------------------------------------------------------------
// CCI-P Input & Output bus structures 
// 
// Users are encouraged to use these for AFU development
//------------------------------------------------------------------------

// Channel 0 : Memory Reads
typedef struct packed {
    t_ccip_ReqMemHdr     hdr;            // Request Header
    logic                rdValid;        // Request Rd Valid
} t_if_ccip_c0_Tx;

// Channel 1 : Memory Writes
typedef struct packed {
    t_ccip_ReqMemHdr     hdr;            // Request Header
    t_ccip_cldata        data;           // Request Data
    logic                wrValid;        // Request Wr Valid
    logic                intrValid;      // Request Intr Valid
} t_if_ccip_c1_Tx;

// Channel 2 : Mmio
typedef struct packed {
    t_ccip_Rsp_MmioHdr   hdr;            // Response Header
    logic                mmioRdValid;    // Response Read Valid
    t_ccip_mmiodata      data;           // Response Data
} t_if_ccip_c2_Tx;

// Wrap all channels
typedef struct packed {
`ifdef CCIP_IF_V0_1
    t_if_ccip_c0_Tx      c0;
    t_if_ccip_c1_Tx      c1;
    t_if_ccip_c2_Tx      c2;
`else
    // Channel 0 : Memory Reads
    t_ccip_ReqMemHdr              C0Hdr;          // Request Header
    logic                         C0RdValid;      // Request Rd Valid

    // Channel 1 : Memory Writes
    t_ccip_ReqMemHdr              C1Hdr;          // Request Header
    logic [CCIP_CLDATA_WIDTH-1:0] C1Data;         // Request Data
    logic                         C1WrValid;      // Request Wr Valid
    logic                         C1IntrValid;    // Request Intr Valid

    // Channel 3 : Mmio
    t_ccip_Rsp_MmioHdr            C2Hdr;          // Response Header
    logic                         C2MmioRdValid;  // Response Read Valid
    logic [CCIP_MMIODATA_WIDTH-1:0]C2Data;         // Response Data
`endif
} t_if_ccip_Tx;


// Channel 0: Memory Reads, Mmio
typedef struct packed {
    t_ccip_RspMemHdr     hdr;            //  Response/Request Header
    t_ccip_cldata        data;           //  Response Data
    logic                wrValid;        //  Response Wr Valid
    logic                rdValid;        //  Response Rd Valid
    logic                umsgValid;      //  Request UMsg Valid
    logic                mmioRdValid;    //  Request MMIO Rd Valid
    logic                mmioWrValid;    //  Request MMIO Wr Valid
} t_if_ccip_c0_Rx;

// Channel 1: Memory Writes
typedef struct packed {
    t_ccip_RspMemHdr     hdr;            //  Response Header
    logic                wrValid;        //  Response Wr Valid
    logic                intrValid;      //  Response Interrupt Valid
} t_if_ccip_c1_Rx;

// Wrap all channels
typedef struct packed {
`ifdef CCIP_IF_V0_1
    logic                c0TxAlmFull;    //  C0 Request Channel Almost Full
    logic                c1TxAlmFull;    //  C1 Request Channel Almost Full

    t_if_ccip_c0_Rx      c0;
    t_if_ccip_c1_Rx      c1;
`else
    // Channel 0: Memory Reads, Mmio
    logic                        C0TxAlmFull;    //  C0 Request Channel Almost Full
    t_ccip_RspMemHdr             C0Hdr;          //  Response/Request Header
    logic [CCIP_CLDATA_WIDTH-1:0]C0Data;         //  Response Data
    logic                        C0WrValid;      //  Response Wr Valid
    logic                        C0RdValid;      //  Response Rd Valid
    logic                        C0UMsgValid;    //  Request UMsg Valid
    logic                        C0MmioRdValid;  //  Request MMIO Rd Valid
    logic                        C0MmioWrValid;  //  Request MMIO Wr Valid

    // Channel 1: Memory Writes
    logic                        C1TxAlmFull;    //  C1 Request Channel Almost Full
    t_ccip_RspMemHdr             C1Hdr;          //  Response Header
    logic                        C1WrValid;      //  Response Wr Valid
    logic                        C1IntrValid;    //  Response Interrupt Valid
`endif
} t_if_ccip_Rx;

endpackage
