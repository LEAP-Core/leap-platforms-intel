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
//  to specify the physical interface.  E.g. USE_CCI_P.
//
// ========================================================================

package cci_mpf_if_pkg;

    import ccip_if_pkg::*;
    import ccis_if_pkg::*;

    //
    // Most data structures are passed unchanged from the chosen interface
    // class to the generic name.  The exception is CLADDR becoming
    // CL_PADDR in order to differentiate between physical and virtual
    // addresses inside MPF.
    //

`ifdef USE_CCI_P
    foo bar baz
`endif

`ifdef USE_CCI_S

    parameter CCI_CL_PADDR_WIDTH = CCIS_CLADDR_WIDTH;
    parameter CCI_CLDATA_WIDTH = CCIS_CLDATA_WIDTH;
    parameter CCI_MDATA_WIDTH = CCIS_MDATA_WIDTH;

    typedef t_ccis_claddr t_cci_cl_paddr;
    typedef t_ccis_cldata t_cci_cldata;
    typedef t_ccis_mdata t_cci_mdata;

    typedef t_ccis_req t_cci_req;
    typedef t_ccis_rsp t_cci_rsp;

    typedef t_ccis_ReqMemHdr t_cci_ReqMemHdr;
    parameter CCI_TX_MEMHDR_WIDTH = CCIS_TX_MEMHDR_WIDTH;

    typedef t_ccis_RspMemHdr t_cci_RspMemHdr;
    parameter CCI_RX_MEMHDR_WIDTH = CCIS_RX_MEMHDR_WIDTH;

    typedef t_if_ccis_Tx t_if_cci_Tx;
    typedef t_if_ccis_Rx t_if_cci_Rx;

`endif

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
    parameter CCI_CL_VADDR_WIDTH = 64 - $clog2(CCI_CLDATA_WIDTH >> 3);
    typedef logic [CCI_CL_VADDR_WIDTH-1:0] t_cci_cl_vaddr;

    // Difference in size between PADDR and VADDR.
    parameter CCI_CL_VADDR_EXT_WIDTH = CCI_CL_VADDR_WIDTH - CCI_CL_PADDR_WIDTH;
    typedef logic [CCI_CL_VADDR_EXT_WIDTH-1:0] t_cci_cl_vaddr_ext;

    //
    // Extension to the request header exposed in the MPF interface to
    // the AFU and used inside MPF.  The extension is dropped before
    // requests reach the QLP.
    //
    typedef struct packed {
        // Extra bits required to hold a virtual address
        t_cci_cl_vaddr_ext addressExt;

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
        t_cci_ReqMemHdr        base;
    } t_cci_mpf_ReqMemHdr;


    // ====================================================================
    //
    //   Helper functions to hide the underlying data structures.
    //
    // ====================================================================

    function automatic t_cci_cl_vaddr getReqVAddrMPF(
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


    function automatic t_cci_mpf_ReqMemHdr genReqHeaderMPF(
        input t_cci_req      requestType,
        input t_cci_cl_vaddr address,
        input t_cci_mdata    mdata,
        input logic          checkLoadStoreOrder = 1'b1,
        input logic          addrIsVirtual = 1'b1
        );

        t_cci_mpf_ReqMemHdr h;

        h.ext.addressExt = address[CCI_CL_VADDR_WIDTH-1 : CCI_CL_PADDR_WIDTH];
        h.ext.checkLoadStoreOrder = checkLoadStoreOrder;
        h.ext.addrIsVirtual = addrIsVirtual;

        h.base = t_cci_ReqMemHdr'(0);
        h.base.req_type = requestType;
        h.base.address = address[CCI_CL_PADDR_WIDTH-1:0];
        h.base.mdata = mdata;

        return h;
    endfunction


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

endpackage // cci_mpf_if
