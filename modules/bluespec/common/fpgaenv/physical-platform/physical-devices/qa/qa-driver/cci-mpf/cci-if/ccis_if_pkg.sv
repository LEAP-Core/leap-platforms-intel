//
// CCI-S interface spec
//
package ccis_if_pkg;

//=====================================================================
// CCI-S interface defines
//=====================================================================
parameter CCIS_CLADDR_WIDTH      = 32;
parameter CCIS_CLDATA_WIDTH      = 512;
parameter CCIS_MDATA_WIDTH       = 13;

// Base types
//----------------------------------------------------------------------
typedef logic [CCIS_CLADDR_WIDTH-1:0] t_ccis_claddr;
typedef logic [CCIS_CLDATA_WIDTH-1:0] t_ccis_cldata;
typedef logic [CCIS_MDATA_WIDTH-1:0] t_ccis_mdata;

// Request Type  Encodings
//----------------------------------------------------------------------
typedef enum logic [3:0] {
    eREQ_WRLINE_I  = 4'h1,      // Memory Write with FPGA Cache Hint=Invalid
    eREQ_WRLINE_M  = 4'h2,      // Memory Write with FPGA Cache Hint=Modified
    eREQ_WRFENCE   = 4'h5,      // Memory Write Fence ** NOT SUPPORTED FOR VC_VA channel **
    eREQ_RDLINE_S  = 4'h4,      // Memory Read with FPGA Cache Hint=Shared
    eREQ_RDLINE_I  = 4'h6,      // Memory Read with FPGA Cache Hint=Invalid
    eREQ_INTR      = 4'h8       // Interrupt the CPU ** NOT SUPPORTED CURRENTLY **
} t_ccis_req;

// Response Type  Encodings
//----------------------------------------------------------------------
typedef enum logic [3:0] {
    eRSP_WRLINE = 4'h1,         // Memory Write
    eRSP_RDLINE = 4'h4,         // Memory Read
    eRSP_INTR   = 4'h8,         // Interrupt delivered to the CPU ** NOT SUPPORTED CURRENTLY **
    eRSP_UMSG   = 4'hF          // UMsg received ** NOT SUPPORTED CURRENTLY **
} t_ccis_rsp;

//
// Structures for Request and Response headers
//----------------------------------------------------------------------
typedef struct packed {
    logic [4:0]     rsvd2;
    t_ccis_req      req_type;
    logic [5:0]     rsvd1;
    t_ccis_claddr   address;
    logic           rsvd0;
    t_ccis_mdata    mdata;
} t_ccis_ReqMemHdr;
parameter CCIS_TX_MEMHDR_WIDTH = $bits(t_ccis_ReqMemHdr);

typedef struct packed {
    t_ccis_rsp      resp_type;
    logic           rsvd0;
    t_ccis_mdata    mdata;
} t_ccis_RspMemHdr;
parameter CCIS_RX_MEMHDR_WIDTH = $bits(t_ccis_RspMemHdr);

//------------------------------------------------------------------------
// CCI-S Input & Output bus structures 
// 
// Users are encouraged to use these for AFU development
//------------------------------------------------------------------------

// Channel 0 : Memory Reads
typedef struct packed {
    t_ccis_ReqMemHdr     hdr;            // Request Header
    logic                rdValid;        // Request Rd Valid
} t_if_ccis_c0_Tx;

// Channel 1 : Memory Writes
typedef struct packed {
    t_ccis_ReqMemHdr     hdr;            // Request Header
    t_ccis_cldata        data;           // Request Data
    logic                wrValid;        // Request Wr Valid
    logic                intrValid;      // Request Intr Valid
} t_if_ccis_c1_Tx;

// Wrap all channels
typedef struct packed {
    t_if_ccis_c0_Tx      c0;
    t_if_ccis_c1_Tx      c1;
} t_if_ccis_Tx;


// Channel 0: Memory Reads
typedef struct packed {
    logic                txAlmFull;      //  C0 Request Channel Almost Full
    t_ccis_RspMemHdr     hdr;            //  Response/Request Header
    t_ccis_cldata        data;           //  Response Data
    logic                wrValid;        //  Response Wr Valid
    logic                rdValid;        //  Response Rd Valid
    logic                cfgValid;       //  Configuration write request
    logic                umsgValid;      //  Request UMsg Valid
    logic                intrValid;      //  Response Interrupt Valid
} t_if_ccis_c0_Rx;

// Channel 1: Memory Writes
typedef struct packed {
    logic                txAlmFull;      //  C1 Request Channel Almost Full
    t_ccis_RspMemHdr     hdr;            //  Response Header
    logic                wrValid;        //  Response Wr Valid
    logic                intrValid;      //  Response Interrupt Valid
} t_if_ccis_c1_Rx;

// Wrap all channels
typedef struct packed {
    t_if_ccis_c0_Rx      c0;
    t_if_ccis_c1_Rx      c1;
} t_if_ccis_Rx;

endpackage
