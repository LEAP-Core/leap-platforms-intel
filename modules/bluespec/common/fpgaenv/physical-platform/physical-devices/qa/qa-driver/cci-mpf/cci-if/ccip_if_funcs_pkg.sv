//
// Functions that operate on CCI-P data types.
//

package ccip_if_funcs_pkg;

    import ccip_if_pkg::*;

    function automatic t_ccip_ReqMemHdr ccip_updMemReqHdrRsvd(
        input t_ccip_ReqMemHdr h
        );

        t_ccip_ReqMemHdr h_out = h;
        h_out.rsvd1 = 0;
        h_out.rsvd0 = 0;

        return h_out;
    endfunction

    function automatic t_if_ccip_c0_Tx ccip_c0TxClearValids();
        t_if_ccip_c0_Tx r = 'x;
        r.rdValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c1_Tx ccip_c1TxClearValids();
        t_if_ccip_c1_Tx r = 'x;
        r.wrValid = 0;
        r.intrValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c2_Tx ccip_c2TxClearValids();
        t_if_ccip_c2_Tx r = 'x;
        r.mmioRdValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c0_Rx ccip_c0RxClearValids();
        t_if_ccip_c0_Rx r = 'x;
        r.wrValid = 0;
        r.rdValid = 0;
        r.umsgValid = 0;
        r.mmioRdValid = 0;
        r.mmioWrValid = 0;
        return r;
    endfunction

    function automatic t_if_ccip_c1_Rx ccip_c1RxClearValids();
        t_if_ccip_c1_Rx r = 'x;
        r.wrValid = 0;
        r.intrValid = 0;
        return r;
    endfunction

    function automatic logic ccip_c0RxIsValid(
        input t_if_ccip_c0_Rx r
        );

        return r.wrValid ||
               r.rdValid ||
               r.umsgValid ||
               r.mmioRdValid ||
               r.mmioWrValid;
    endfunction

    function automatic logic ccip_c1RxIsValid(
        input t_if_ccip_c1_Rx r
        );

        return r.wrValid ||
               r.intrValid;
    endfunction

endpackage // ccip_if_funcs_pkg
