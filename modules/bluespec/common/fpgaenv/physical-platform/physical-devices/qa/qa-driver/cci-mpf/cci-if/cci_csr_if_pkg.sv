//
// CSR functions to make reading CSRs look similar on CCI-S and CCI-P
//

package cci_csr_if_pkg;
    import cci_mpf_if_pkg::*;

    //
    // Is the incoming request a CSR write?
    //
    function automatic logic cci_csr_isWrite(
        input t_if_cci_c0_Rx r
        );

`ifdef USE_PLATFORM_CCIS
        // CCI-S maps CSRs to configuration messages
        return r.cfgValid;
`endif

`ifdef USE_PLATFORM_CCIP
        // CCI-P maps CSRs to mmio reads and writes
        return r.mmioWrValid;
`endif
    endfunction


    //
    // Is the incoming request a CSR read?
    //
    function automatic logic cci_csr_isRead(
        input t_if_cci_c0_Rx r
        );

`ifdef USE_PLATFORM_CCIS
        // CCI-S doesn't have CSR reads
        return 1'b0;
`endif

`ifdef USE_PLATFORM_CCIP
        // CCI-P maps CSRs to mmio reads and writes
        return r.mmioRdValid;
`endif
    endfunction


    //
    // Get the CSR address of a read/write request.
    //
    function automatic logic [8:0] cci_csr_getTid(
        input t_if_cci_c0_Rx r
        );

`ifdef USE_PLATFORM_CCIS
        return 8'b0;
`endif

`ifdef USE_PLATFORM_CCIP
        t_cci_Req_MmioHdr h = t_cci_Req_MmioHdr'(r.hdr);
        return h.tid;
`endif
    endfunction


    //
    // Get the CSR tid from a read request.
    //
    function automatic t_cci_mmioaddr cci_csr_getAddress(
        input t_if_cci_c0_Rx r
        );

`ifdef USE_PLATFORM_CCIS
        // CCI-S maps CSRs to configuration messages
        return t_cci_mmioaddr'(r.hdr);
`endif

`ifdef USE_PLATFORM_CCIP
        // CCI-P maps CSRs to mmio reads and writes
        t_cci_Req_MmioHdr h = t_cci_Req_MmioHdr'(r.hdr);
        return h.address;
`endif
    endfunction

endpackage // cci_csr_if_pkg
