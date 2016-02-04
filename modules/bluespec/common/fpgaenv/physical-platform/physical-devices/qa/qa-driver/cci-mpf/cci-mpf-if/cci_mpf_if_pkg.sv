//
// Abstract CCI wrapper around hardware-specific CCI specifications.
//
// In addition to providing functions for accessing an updating CCI data
// structions, the abstraction extends the CCI header to add support
// for virtual memory addresses as well as control of memory protocol
// factory (MPF) features such as enabling or disabling memory ordering.
//
// Naming:
//
//   - This module imports data structures from the base interface
//     (e.g. CCI-P) and renames the underlying data structures as
//     t_cci_... from the version-specific names, e.g. t_ccip_....
//
//   - MPF-specific data structures are extensions of t_cci structures
//     and are named t_cci_mpf_....
//

// ========================================================================
//
//  Before importing this module, define exactly one preprocessor macro
//  to specify the physical interface.  E.g. USE_PLATFORM_CCIP.
//
// ========================================================================

package cci_mpf_if_pkg;
    import ccis_if_pkg::*;
    import ccis_if_funcs_pkg::*;

    import ccip_if_pkg::*;
    import ccip_if_funcs_pkg::*;

    //
    // MPF's CCI is an extension of the platform's base CCI:
    //
    //  - It offers virtual addressing. The base CCI address field is
    //    defined to be large enough for either virtual or physical
    //    addresses. MPF adds a flag to indicate whether a given request's
    //    address is virtual or physical.
    //
    //  - MPF provides functions for platform-independent manipulation
    //    of CCI structures. It defines platform agnostic names,
    //    e.g. t_cci_claddr instead of t_ccip_claddr. Objects with
    //    MPF-specific data are given a name that includes "mpf", such
    //    as t_cci_mpf_ReqMemHdr.
    //

    //
    // Derive abstract CCI from CCI-P, which is a superset of all previous
    // platforms.
    //
    parameter CCI_CLADDR_WIDTH = CCIP_CLADDR_WIDTH;
    parameter CCI_CLDATA_WIDTH = CCIP_CLDATA_WIDTH;

    parameter CCI_MMIOADDR_WIDTH = CCIP_MMIOADDR_WIDTH;
    parameter CCI_MMIODATA_WIDTH = CCIP_MMIODATA_WIDTH;

`ifdef USE_PLATFORM_CCIS
    parameter CCI_MDATA_WIDTH = CCIS_MDATA_WIDTH;
    parameter CCI_ALMOST_FULL_THRESHOLD = CCIS_ALMOST_FULL_THRESHOLD;
`endif
`ifdef USE_PLATFORM_CCIP
    parameter CCI_MDATA_WIDTH = CCIP_MDATA_WIDTH;
    parameter CCI_ALMOST_FULL_THRESHOLD = CCIP_ALMOST_FULL_THRESHOLD;
`endif

    typedef t_ccip_claddr t_cci_claddr;
    typedef t_ccip_cldata t_cci_cldata;
    typedef t_ccip_mdata t_cci_mdata;

    typedef t_ccip_vc t_cci_vc;
    typedef t_ccip_cl_num t_cci_cl_num;

    typedef t_ccip_mmioaddr t_cci_mmioaddr;
    typedef t_ccip_mmiodata t_cci_mmiodata;
    typedef t_ccip_tid t_cci_tid;

    typedef t_ccip_req t_cci_req;
    typedef t_ccip_rsp t_cci_rsp;

    typedef t_ccip_ReqMemHdr t_cci_ReqMemHdr;
    parameter CCI_TX_MEMHDR_WIDTH = CCIP_TX_MEMHDR_WIDTH;

    typedef t_ccip_RspMemHdr t_cci_RspMemHdr;
    parameter CCI_RX_MEMHDR_WIDTH = CCIP_RX_MEMHDR_WIDTH;

    typedef t_ccip_Req_MmioHdr t_cci_Req_MmioHdr;
    parameter CCI_RX_MMIOHDR_WIDTH = CCIP_RX_MMIOHDR_WIDTH;

    typedef t_ccip_Rsp_MmioHdr t_cci_Rsp_MmioHdr;
    parameter CCI_TX_MMIOHDR_WIDTH = CCIP_TX_MMIOHDR_WIDTH;

    typedef t_if_ccip_c0_Tx t_if_cci_c0_Tx;
    typedef t_if_ccip_c1_Tx t_if_cci_c1_Tx;
    typedef t_if_ccip_c2_Tx t_if_cci_c2_Tx;
    typedef t_if_ccip_Tx t_if_cci_Tx;

    typedef t_if_ccip_c0_Rx t_if_cci_c0_Rx;
    typedef t_if_ccip_c1_Rx t_if_cci_c1_Rx;
    typedef t_if_ccip_Rx t_if_cci_Rx;

    function automatic t_cci_ReqMemHdr cci_updMemReqHdrRsvd(
        input t_cci_ReqMemHdr h
        );
        return ccip_updMemReqHdrRsvd(h);
    endfunction

    function automatic t_if_cci_c0_Tx cci_c0TxClearValids();
        return ccip_c0TxClearValids();
    endfunction

    function automatic t_if_cci_c1_Tx cci_c1TxClearValids();
        return ccip_c1TxClearValids();
    endfunction

    function automatic t_if_cci_c0_Rx cci_c0RxClearValids();
        return ccip_c0RxClearValids();
    endfunction

    function automatic t_if_cci_c1_Rx cci_c1RxClearValids();
        return ccip_c1RxClearValids();
    endfunction

    function automatic logic cci_c0RxIsValid(
        input t_if_cci_c0_Rx r
        );
        return ccip_c0RxIsValid(r);
    endfunction

    function automatic logic cci_c1RxIsValid(
        input t_if_cci_c1_Rx r
        );
        return ccip_c1RxIsValid(r);
    endfunction


    // ====================================================================
    //
    //   MPF-specific header.
    //
    // ====================================================================

    // CCI_CL_ADDR_WIDTH must be at least as large as both the virtual
    // and physical address widths. On CCI-P both are the same.
    parameter CCI_MPF_CL_PADDR_WIDTH = CCI_CLADDR_WIDTH;
    parameter CCI_MPF_CL_VADDR_WIDTH = CCI_CLADDR_WIDTH;

    //
    // The CCI MPF request header adds fields that are used only for
    // requests flowing from the AFU and through the memory properties
    // factory.  As requests leave MPF and enter the physical CCI the
    // extra fields are dropped.
    //
    // Fields include extra bits to specify virtual addresses and some
    // memory ordering controls.
    //

    //
    // Extension to the request header exposed in the MPF interface to
    // the AFU and used inside MPF.  The extension is dropped before
    // requests reach the FIU.
    //
    typedef struct packed {
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
    //   TX channels with MPF extension
    //
    // ====================================================================

    //
    // Rewrite the TX channel structs to include the MPF extended header.
    //

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


    // ====================================================================
    //
    //   Helper functions to hide the underlying data structures.
    //
    // ====================================================================

    function automatic t_cci_claddr cci_mpf_getReqAddr(
        input t_cci_mpf_ReqMemHdr h
        );

        return h.base.address;
    endfunction


    function automatic logic cci_mpf_getReqCheckOrder(
        input t_cci_mpf_ReqMemHdr h
        );

        return h.ext.checkLoadStoreOrder;
    endfunction


    function automatic logic cci_mpf_getReqAddrIsVirtual(
        input t_cci_mpf_ReqMemHdr h
        );

        return h.ext.addrIsVirtual;
    endfunction


    // Update an existing request header with a new virtual address.
    function automatic t_cci_mpf_ReqMemHdr cci_mpf_updReqVAddr(
        input t_cci_mpf_ReqMemHdr h,
        input t_cci_claddr        address
        );

        h.ext.addrIsVirtual = 1'b1;
        h.base.address = address;

        return h;
    endfunction


    // Generate a new request header.  With so many parameters and defaults
    // we use a struct to pass non-basic parameters.
    typedef struct {
        logic         checkLoadStoreOrder;
        logic         addrIsVirtual;
        t_cci_vc      vc_sel;
        t_cci_cl_num  cl_num;
    } t_cci_mpf_ReqMemHdrParams;

    // Default value for request header construction. It takes only one
    // option (whether or not the reqest is a VA) to keep the interface
    // simple and because answering VA vs. PA separates the two main
    // categories of requests.
    function automatic t_cci_mpf_ReqMemHdrParams cci_mpf_defaultReqHdrParams(
        input int addrIsVirtual = 1
        );

        t_cci_mpf_ReqMemHdrParams p;
        p.checkLoadStoreOrder = 1'b0;      // Default hardware behavior
        p.addrIsVirtual = 1'(addrIsVirtual);
        p.vc_sel = eVC_VL0;
        p.cl_num = 0;
        return p;
    endfunction

    function automatic t_cci_mpf_ReqMemHdr cci_mpf_genReqHdr(
        input t_cci_req                 requestType,
        input t_cci_claddr              address,
        input t_cci_mdata               mdata,
        input t_cci_mpf_ReqMemHdrParams params
        );

        t_cci_mpf_ReqMemHdr h;

        h.base = t_cci_ReqMemHdr'(0);
        h = cci_mpf_updReqVAddr(h, address);

        h.ext.checkLoadStoreOrder = params.checkLoadStoreOrder;
        h.ext.addrIsVirtual = params.addrIsVirtual;

        h.base.req_type = requestType;
        h.base.mdata = mdata;
        h.base.vc_sel = params.vc_sel;
        h.base.cl_num = params.cl_num;

        return h;
    endfunction

    // Same as MPF version of genReqHdr but return only the base header
    function automatic t_cci_ReqMemHdr cci_genReqHdr(
        input t_cci_req                 requestType,
        input t_cci_claddr              address,
        input t_cci_mdata               mdata,
        input t_cci_mpf_ReqMemHdrParams params
        );

        t_cci_mpf_ReqMemHdr h = cci_mpf_genReqHdr(requestType,
                                                  address,
                                                  mdata,
                                                  params);
        return h.base;
    endfunction


    // Generate a new request header from a base CCI header
    function automatic t_cci_mpf_ReqMemHdr cci_mpf_cvtReqHdrFromBase(
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
    function automatic t_cci_RspMemHdr cci_genRspHdr(
        input t_cci_rsp     responseType,
        input t_cci_mdata   mdata
        );

        t_cci_RspMemHdr h;
        h = t_cci_RspMemHdr'(0);

        h.resp_type = responseType;
        h.mdata = mdata;

        return h;
    endfunction


    // Generate an MPF C0 TX from a base struct
    function automatic t_if_cci_mpf_c0_Tx cci_mpf_cvtC0TxFromBase(
        input t_if_cci_c0_Tx b
        );

        t_if_cci_mpf_c0_Tx m;

        m.hdr = cci_mpf_cvtReqHdrFromBase(b.hdr);
        m.rdValid = b.rdValid;

        return m;
    endfunction


    // Generate an MPF C1 TX from a base struct
    function automatic t_if_cci_mpf_c1_Tx cci_mpf_cvtC1TxFromBase(
        input t_if_cci_c1_Tx b
        );

        t_if_cci_mpf_c1_Tx m;

        m.hdr = cci_mpf_cvtReqHdrFromBase(b.hdr);
        m.data = b.data;
        m.wrValid = b.wrValid;
        m.intrValid = b.intrValid;

        return m;
    endfunction


    // Generate a base C0 TX from an MPF struct.
    //  *** This only works if the address stored in the MPF header is
    //  *** physical.
    function automatic t_if_cci_c0_Tx cci_mpf_cvtC0TxToBase(
        input t_if_cci_mpf_c0_Tx m
        );

        t_if_cci_c0_Tx b;

        b.hdr = m.hdr.base;
        b.rdValid = m.rdValid;

        return b;
    endfunction


    // Generate a base C1 TX from an MPF struct.
    //  *** This only works if the address stored in the MPF header is
    //  *** physical.
    function automatic t_if_cci_c1_Tx cci_mpf_cvtC1TxToBase(
        input t_if_cci_mpf_c1_Tx m
        );

        t_if_cci_c1_Tx b;

        b.hdr = m.hdr.base;
        b.data = m.data;
        b.wrValid = m.wrValid;
        b.intrValid = m.intrValid;

        return b;
    endfunction


    // Initialize an MPF C0 TX with all valid bits clear
    function automatic t_if_cci_mpf_c0_Tx cci_mpf_c0TxClearValids();
        t_if_cci_mpf_c0_Tx r = 'x;
        r.rdValid = 0;
        return r;
    endfunction

    // Initialize an MPF C1 TX with all valid bits clear
    function automatic t_if_cci_mpf_c1_Tx cci_mpf_c1TxClearValids();
        t_if_cci_mpf_c1_Tx r = 'x;
        r.wrValid = 0;
        r.intrValid = 0;
        return r;
    endfunction


    // Mask the valid bits in an MPF C0 TX
    function automatic t_if_cci_mpf_c0_Tx cci_mpf_c0TxMaskValids(
        input t_if_cci_mpf_c0_Tx r,
        input logic mask
        );

        r.rdValid = r.rdValid && mask;
        return r;
    endfunction

    // Mask the valid bits in an MPF C1 TX
    function automatic t_if_cci_mpf_c1_Tx cci_mpf_c1TxMaskValids(
        input t_if_cci_mpf_c1_Tx r,
        input logic mask
        );

        r.wrValid = r.wrValid && mask;
        r.intrValid = r.intrValid && mask;
        return r;
    endfunction


    // Does an MPF C0 TX have a valid request?
    function automatic logic cci_mpf_c0TxIsValid(
        input t_if_cci_mpf_c0_Tx r
        );

        return r.rdValid;
    endfunction

    // Does an MPF C1 TX have a valid request?
    function automatic logic cci_mpf_c1TxIsValid(
        input t_if_cci_mpf_c1_Tx r
        );

        return r.wrValid || r.intrValid;
    endfunction


    // Generate an MPF C0 TX read request given a header
    function automatic t_if_cci_mpf_c0_Tx cci_mpf_genC0TxReadReq(
        input t_cci_mpf_ReqMemHdr h,
        input logic rdValid
        );

        t_if_cci_mpf_c0_Tx r = cci_mpf_c0TxClearValids();
        r.hdr = h;
        r.rdValid = rdValid;

        return r;
    endfunction

    // Generate an MPF C1 TX write request given a header and data
    function automatic t_if_cci_mpf_c1_Tx cci_mpf_genC1TxWriteReq(
        input t_cci_mpf_ReqMemHdr h,
        input t_cci_cldata data,
        input logic wrValid
        );

        t_if_cci_mpf_c1_Tx r = cci_mpf_c1TxClearValids();
        r.hdr = h;
        r.data = data;
        r.wrValid = wrValid;

        return r;
    endfunction


    // Canonicalize an MPF C0 TX request
    function automatic t_if_cci_mpf_c0_Tx cci_mpf_updC0TxCanonical(
        input t_if_cci_mpf_c0_Tx r
        );

        t_if_cci_mpf_c0_Tx r_out = r;
        t_cci_ReqMemHdr h = r.hdr.base;

        // Make sure req_type matches one-hot flags
        if (! cci_mpf_c0TxIsValid(r))
        begin
            h.req_type = t_cci_req'(0);
        end

        r_out.hdr.base = h;

        return r_out;
    endfunction

    // Canonicalize an MPF C1 TX request
    function automatic t_if_cci_mpf_c1_Tx cci_mpf_updC1TxCanonical(
        input t_if_cci_mpf_c1_Tx r
        );


        t_if_cci_mpf_c1_Tx r_out = r;
        t_cci_ReqMemHdr h = r.hdr.base;

        // Make sure req_type matches one-hot flags
        if (! cci_mpf_c1TxIsValid(r))
        begin
            h.req_type = t_cci_req'(0);
        end

        r_out.hdr.base = cci_updMemReqHdrRsvd(h);

        return r_out;
    endfunction

endpackage // cci_mpf_if
