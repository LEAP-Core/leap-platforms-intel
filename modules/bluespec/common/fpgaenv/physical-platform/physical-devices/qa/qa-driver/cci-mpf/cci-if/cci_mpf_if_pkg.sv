//
// Abstract CCI wrapper around hardware-specific CCI specifications.
//
// In addition to providing functions for accessing an updating CCI data
// structions, the abstraction extends the CCI header to add support
// for virtual memory addresses as well as control of memory protocol
// factory (MPF) features such as enabling or disabling memory ordering.
//

// ========================================================================
//
//  Before importing this module, define exactly one preprocessor macro
//  to specify the physical interface.  E.g. USE_PLATFORM_CCI_P.
//
// ========================================================================

package cci_mpf_if_pkg;

    //
    // Most data structures are passed unchanged from the chosen interface
    // class to the generic name.  The exception is CLADDR becoming
    // CL_PADDR in order to differentiate between physical and virtual
    // addresses inside MPF.
    //

`ifdef USE_PLATFORM_CCI_P
    import ccip_if_pkg::*;
`endif

`ifdef USE_PLATFORM_CCI_S
    import ccis_if_pkg::*;

    parameter CCI_CL_PADDR_WIDTH = CCIS_CLADDR_WIDTH;
    parameter CCI_CLDATA_WIDTH = CCIS_CLDATA_WIDTH;
    parameter CCI_MDATA_WIDTH = CCIS_MDATA_WIDTH;
    parameter CCI_ALMOST_FULL_THRESHOLD = CCIS_ALMOST_FULL_THRESHOLD;

    typedef t_ccis_claddr t_cci_cl_paddr;
    typedef t_ccis_cldata t_cci_cldata;
    typedef t_ccis_mdata t_cci_mdata;

    typedef t_ccis_req t_cci_req;
    typedef t_ccis_rsp t_cci_rsp;

    typedef t_ccis_ReqMemHdr t_cci_ReqMemHdr;
    parameter CCI_TX_MEMHDR_WIDTH = CCIS_TX_MEMHDR_WIDTH;

    typedef t_ccis_RspMemHdr t_cci_RspMemHdr;
    parameter CCI_RX_MEMHDR_WIDTH = CCIS_RX_MEMHDR_WIDTH;

    typedef t_if_ccis_c0_Tx t_if_cci_c0_Tx;
    typedef t_if_ccis_c1_Tx t_if_cci_c1_Tx;
    typedef t_if_ccis_Tx t_if_cci_Tx;

    typedef t_if_ccis_c0_Rx t_if_cci_c0_Rx;
    typedef t_if_ccis_c1_Rx t_if_cci_c1_Rx;
    typedef t_if_ccis_Rx t_if_cci_Rx;

    function automatic t_if_cci_c0_Tx cci_c0TxClearValids();
        return ccis_c0TxClearValids();
    endfunction

    function automatic t_if_cci_c1_Tx cci_c1TxClearValids();
        return ccis_c1TxClearValids();
    endfunction

    function automatic t_if_cci_c0_Rx cci_c0RxClearValids();
        return ccis_c0RxClearValids();
    endfunction

    function automatic t_if_cci_c1_Rx cci_c1RxClearValids();
        return ccis_c1RxClearValids();
    endfunction

`endif

    // ====================================================================
    //
    //   Re-define some common enumerations in the MPF package space.
    //
    // ====================================================================

/*
    typedef enum logic [3:0] {
        eREQ_WRLINE_I  = 4'h1,      // Memory Write with FPGA Cache Hint=Invalid
        eREQ_WRLINE_M  = 4'h2,      // Memory Write with FPGA Cache Hint=Modified
        eREQ_WRFENCE   = 4'h5,      // Memory Write Fence ** NOT SUPPORTED FOR VC_VA channel **
        eREQ_RDLINE_S  = 4'h4,      // Memory Read with FPGA Cache Hint=Shared
        eREQ_RDLINE_I  = 4'h6,      // Memory Read with FPGA Cache Hint=Invalid
        eREQ_INTR      = 4'h8       // Interrupt the CPU ** NOT SUPPORTED CURRENTLY **
    } t_cci_req;

    typedef enum logic [3:0] {
        eRSP_WRLINE = 4'h1,         // Memory Write
        eRSP_RDLINE = 4'h4,         // Memory Read
        eRSP_INTR   = 4'h8,         // Interrupt delivered to the CPU ** NOT SUPPORTED CURRENTLY **
        eRSP_UMSG   = 4'hF          // UMsg received ** NOT SUPPORTED CURRENTLY **
    } t_cci_rsp;
*/

    // ====================================================================
    //
    //   MPF-specific header.
    //
    // ====================================================================

    //
    // The CCI MPF request header adds fields that are used only for
    // requests flowing from the AFU and through the memory protocol
    // factory.  As requests leave MPF and enter the physical CCI the
    // extra fields are dropped.
    //
    // Fields include extra bits to specify virtual addresses and some
    // memory ordering controls.
    //

    // Bits in a VA to address a cache line is 64 minus the byte-level
    // address bits internal to a single cache line.
    parameter CCI_MPF_CL_VADDR_WIDTH = 64 - $clog2(CCI_CLDATA_WIDTH >> 3);
    typedef logic [CCI_MPF_CL_VADDR_WIDTH-1:0] t_cci_mpf_cl_vaddr;

    // Difference in size between PADDR and VADDR.
    parameter CCI_MPF_CL_VADDR_EXT_WIDTH = CCI_MPF_CL_VADDR_WIDTH - CCI_CL_PADDR_WIDTH;
    typedef logic [CCI_MPF_CL_VADDR_EXT_WIDTH-1:0] t_cci_mpf_cl_vaddr_ext;

    //
    // Extension to the request header exposed in the MPF interface to
    // the AFU and used inside MPF.  The extension is dropped before
    // requests reach the QLP.
    //
    typedef struct packed {
        // Extra bits required to hold a virtual address
        t_cci_mpf_cl_vaddr_ext addressExt;

        // Enforce load/store and store/store ordering within lines?
        // Setting this to zero bypasses ordering logic for this request.
        logic checkLoadStoreOrder;

        // Is the address in the header virtual (1) or physical (0)?
        logic addrIsVirtual;
    } t_cci_mpf_ReqMemHdrExt;

    //
    // A full header
    //
    typedef struct packed {
        t_cci_mpf_ReqMemHdrExt ext;

        // The base component must be last in order to preserve the header
        // property that mdata is in the low bits.  Some code treats the
        // header as opaque and manipulates the mdata bits without using
        // the struct fields.
        t_cci_ReqMemHdr        base;
    } t_cci_mpf_ReqMemHdr;

    parameter CCI_MPF_TX_MEMHDR_WIDTH = $bits(t_cci_mpf_ReqMemHdr);


    // ====================================================================
    //
    //   Helper functions to hide the underlying data structures.
    //
    // ====================================================================

    // Virtual address is stored in a pair of fields: the field that
    // will ultimately hold the physical address and an overflow field.
    function automatic t_cci_mpf_cl_vaddr getReqVAddrMPF(
        input t_cci_mpf_ReqMemHdr h
        );

        return {h.ext.addressExt, h.base.address};
    endfunction


    function automatic logic getReqCheckOrderMPF(
        input t_cci_mpf_ReqMemHdr h
        );

        return h.ext.checkLoadStoreOrder;
    endfunction


    function automatic logic getReqAddrIsVirtualMPF(
        input t_cci_mpf_ReqMemHdr h
        );

        return h.ext.addrIsVirtual;
    endfunction


    // Update an existing request header with a new virtual address.
    function automatic t_cci_mpf_ReqMemHdr updReqVAddrMPF(
        input t_cci_mpf_ReqMemHdr h,
        input t_cci_mpf_cl_vaddr  address
        );

        h.ext.addressExt = address[CCI_MPF_CL_VADDR_WIDTH-1 : CCI_CL_PADDR_WIDTH];
        h.base.address = address[CCI_CL_PADDR_WIDTH-1:0];

        return h;
    endfunction


    // Generate a new request header
    function automatic t_cci_mpf_ReqMemHdr genReqHeaderMPF(
        input t_cci_req          requestType,
        input t_cci_mpf_cl_vaddr address,
        input t_cci_mdata        mdata,
        input logic              checkLoadStoreOrder = 1'b1,
        input logic              addrIsVirtual = 1'b1
        );

        t_cci_mpf_ReqMemHdr h;

        h.base = t_cci_ReqMemHdr'(0);
        h = updReqVAddrMPF(h, address);

        h.ext.checkLoadStoreOrder = checkLoadStoreOrder;
        h.ext.addrIsVirtual = addrIsVirtual;

        h.base.req_type = requestType;
        h.base.mdata = mdata;

        return h;
    endfunction


    // Generate a new request header from a base CCI header
    function automatic t_cci_mpf_ReqMemHdr genReqHeaderMPFFromBase(
        input t_cci_ReqMemHdr baseHdr
        );

        t_cci_mpf_ReqMemHdr h;

        h.base = baseHdr;

        // Clear the MPF-specific flags in the MPF extended header so
        // that MPF treats the request as a standard CCI request.
        h.ext = 'x;
        h.ext.checkLoadStoreOrder = 0;
        h.ext.addrIsVirtual = 0;

        return h;
    endfunction


    // Generate a new response header
    function automatic t_cci_RspMemHdr genRspHeaderMPF(
        input t_cci_rsp     responseType,
        input t_cci_mdata   mdata
        );

        t_cci_RspMemHdr h;
        h = t_cci_RspMemHdr'(0);

        h.resp_type = responseType;
        h.mdata = mdata;

        return h;
    endfunction


    // ====================================================================
    //
    //   Rewrite the channel request structures to incorporate the
    //   extra MPF header fields.
    //
    // ====================================================================

    // Channel 0 : Memory Reads
    typedef struct packed {
        t_cci_mpf_ReqMemHdr  hdr;            // Request Header
        logic                rdValid;        // Request Rd Valid
    } t_if_cci_mpf_c0_Tx;

    // Channel 1 : Memory Writes
    typedef struct packed {
        t_cci_mpf_ReqMemHdr  hdr;            // Request Header
        t_cci_cldata         data;           // Request Data
        logic                wrValid;        // Request Wr Valid
        logic                intrValid;      // Request Intr Valid
    } t_if_cci_mpf_c1_Tx;

endpackage // cci_mpf_if
