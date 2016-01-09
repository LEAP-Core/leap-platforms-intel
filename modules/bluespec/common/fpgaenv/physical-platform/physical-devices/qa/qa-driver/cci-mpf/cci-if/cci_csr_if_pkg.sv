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
    // Get the CSR address of a read/write request.
    //
    //   We define t_cci_mmioaddr as the configuration register space in
    //   CCI-S to simplify the code.
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
