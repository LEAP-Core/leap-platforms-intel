//
// Debug output for MPF CCI interface.
//

`ifndef CCI_MPF_IF_DBG_VH
`define CCI_MPF_IF_DBG_VH


// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
//
//   This file is INCLUDED by cci_mpf_if.vh.  An interface can't
//   instantiate another module, but it is cleaner to have the debugging
//   code in a separate file.
//
// !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    //
    // Export some struct fields as names so they fields can be seen in
    // waveform viewers.
    //
    // This generates a lot of data so it is enabled only when debug
    // logging is enabled for the interface instance.
    //
    generate
        if (ENABLE_LOG != 0)
        begin : dbg
            logic c0Tx_almFull;
            assign c0Tx_almFull = c0TxAlmFull;

            logic c0Tx_hdr_addrIsVirtual;
            assign c0Tx_hdr_addrIsVirtual = c0Tx.hdr.ext.addrIsVirtual;
            logic c0Tx_hdr_checkLoadStoreOrder;
            assign c0Tx_hdr_checkLoadStoreOrder = c0Tx.hdr.ext.checkLoadStoreOrder;
            t_cci_vc c0Tx_hdr_vc_sel;
            assign c0Tx_hdr_vc_sel = c0Tx.hdr.base.vc_sel;
            t_cci_clLen c0Tx_hdr_cl_len;
            assign c0Tx_hdr_cl_len = c0Tx.hdr.base.cl_len;
            t_cci_c0_req c0Tx_hdr_req_type;
            assign c0Tx_hdr_req_type = c0Tx.hdr.base.req_type;
            t_cci_clAddr c0Tx_hdr_address;
            assign c0Tx_hdr_address = c0Tx.hdr.base.address;
            t_cci_mdata c0Tx_hdr_mdata;
            assign c0Tx_hdr_mdata = c0Tx.hdr.base.mdata;
            logic c0Tx_valid;
            assign c0Tx_valid = c0Tx.valid;

            logic c1Tx_almFull;
            assign c1Tx_almFull = c1TxAlmFull;

            logic c1Tx_hdr_addrIsVirtual;
            assign c1Tx_hdr_addrIsVirtual = c1Tx.hdr.ext.addrIsVirtual;
            logic c1Tx_hdr_checkLoadStoreOrder;
            assign c1Tx_hdr_checkLoadStoreOrder = c1Tx.hdr.ext.checkLoadStoreOrder;
            t_cci_vc c1Tx_hdr_vc_sel;
            assign c1Tx_hdr_vc_sel = c1Tx.hdr.base.vc_sel;
            logic c1Tx_hdr_sop;
            assign c1Tx_hdr_sop = c1Tx.hdr.base.sop;
            t_cci_clLen c1Tx_hdr_cl_len;
            assign c1Tx_hdr_cl_len = c1Tx.hdr.base.cl_len;
            t_cci_c1_req c1Tx_hdr_req_type;
            assign c1Tx_hdr_req_type = c1Tx.hdr.base.req_type;
            t_cci_clAddr c1Tx_hdr_address;
            assign c1Tx_hdr_address = c1Tx.hdr.base.address;
            t_cci_mdata c1Tx_hdr_mdata;
            assign c1Tx_hdr_mdata = c1Tx.hdr.base.mdata;
            t_cci_clData c1Tx_data;
            assign c1Tx_data = c1Tx.data;
            logic c1Tx_valid;
            assign c1Tx_valid = c1Tx.valid;

            t_cci_tid c2Tx_tid;
            assign c2Tx_tid = c2Tx.hdr.tid;
            logic c2Tx_mmioRdValid;
            assign c2Tx_mmioRdValid = c2Tx.mmioRdValid;
            t_cci_mmioData c2Tx_data;
            assign c2Tx_data = c2Tx.data;

            t_cci_vc c0Rx_hdr_vc_used;
            assign c0Rx_hdr_vc_used = c0Rx.hdr.vc_used;
            logic c0Rx_hdr_hit_miss;
            assign c0Rx_hdr_hit_miss = c0Rx.hdr.hit_miss;
            t_ccip_clNum c0Rx_hdr_cl_num;
            assign c0Rx_hdr_cl_num = c0Rx.hdr.cl_num;
            t_ccip_c0_rsp c0Rx_hdr_resp_type;
            assign c0Rx_hdr_resp_type = c0Rx.hdr.resp_type;
            t_ccip_mdata c0Rx_hdr_mdata;
            assign c0Rx_hdr_mdata = c0Rx.hdr.mdata;
            t_ccip_clData c0Rx_rsvd1;
            assign c0Rx_hdr_rsvd1 = c0Rx.hdr.rsvd1;
            t_ccip_clData c0Rx_data;
            assign c0Rx_data = c0Rx.data;
            logic c0Rx_rspValid;
            assign c0Rx_rspValid = c0Rx.rspValid;
            logic c0Rx_mmioRdValid;
            assign c0Rx_mmioRdValid = c0Rx.mmioRdValid;
            logic c0Rx_mmioWrValid;
            assign c0Rx_mmioWrValid = c0Rx.mmioWrValid;

            t_cci_vc c1Rx_hdr_vc_used;
            assign c1Rx_hdr_vc_used = c1Rx.hdr.vc_used;
            logic c1Rx_hdr_hit_miss;
            assign c1Rx_hdr_hit_miss = c1Rx.hdr.hit_miss;
            logic c1Rx_hdr_format;
            assign c1Rx_hdr_format = c1Rx.hdr.format;
            t_ccip_clNum c1Rx_hdr_cl_num;
            assign c1Rx_hdr_cl_num = c1Rx.hdr.cl_num;
            t_ccip_c1_rsp c1Rx_hdr_resp_type;
            assign c1Rx_hdr_resp_type = c1Rx.hdr.resp_type;
            t_ccip_mdata c1Rx_hdr_mdata;
            assign c1Rx_hdr_mdata = c1Rx.hdr.mdata;
            logic c1Rx_rspValid;
            assign c1Rx_rspValid = c1Rx.rspValid;
        end
    endgenerate


    // Print Channel function
    function string print_channel (logic [1:0] vc_sel);
        case (vc_sel)
            2'b00: return "VA ";
            2'b01: return "VL0";
            2'b10: return "VH0";
            2'b11: return "VH1";
        endcase
    endfunction

    // Print Req Type
    function string print_c0_reqtype (t_cci_c0_req req);
        case (req)
            eREQ_RDLINE_S: return "RdLine_S  ";
            eREQ_RDLINE_I: return "RdLine_I  ";
            default:       return "* ERROR * ";
        endcase
    endfunction

    function string print_c1_reqtype (t_cci_c1_req req);
        case (req)
            eREQ_WRLINE_I: return "WrLine_I  ";
            eREQ_WRLINE_M: return "WrLine_M  ";
         // eREQ_WRPUSH_I: return "WRPush_I  ";
            eREQ_WRFENCE:  return "WrFence   ";
         // eREQ_ATOMIC:   return "Atomic    ";
            eREQ_INTR:     return "IntrReq   ";
            default:       return "* ERROR * ";
        endcase
    endfunction

    // Print resp type
    function string print_c0_resptype (t_cci_c0_rsp rsp);
        case (rsp)
            eRSP_RDLINE:  return "RdRsp      ";
            eRSP_UMSG:    return "UmsgRsp    ";
         // eRSP_ATOMIC:  return "AtomicRsp  ";
            default:      return "* ERROR *  ";
        endcase
    endfunction

    function string print_c1_resptype (t_cci_c1_rsp rsp);
        case (rsp)
            eRSP_WRLINE:  return "WrRsp      ";
            eRSP_WRFENCE: return "WrFenceRsp ";
            eRSP_INTR:    return "IntrResp   ";
            default:      return "* ERROR *  ";
        endcase
    endfunction

    // Print CSR data
    function int csr_len(logic [1:0] length);
        case (length)
            2'b0: return 4;
            2'b1: return 8;
            2'b10: return 64;
            default: return 0;
        endcase
    endfunction

 
    initial
    begin : logger_proc
        if (cci_mpf_if_log_fd == -1)
        begin
            cci_mpf_if_log_fd = $fopen(LOG_NAME, "w");
        end

        // Watch traffic
        if (ENABLE_LOG != 0)
        begin
            forever @(posedge clk)
            begin
                // //////////////////////// C0 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Read Request ******************/
                if (! reset && c0Tx.valid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\t%s %x\n",
                            $time,
                            print_channel(c0Tx.hdr.base.vc_sel),
                            c0Tx.hdr.base.cl_len,
                            print_c0_reqtype(c0Tx.hdr.base.req_type),
                            c0Tx.hdr.base.mdata,
                            (c0Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            c0Tx.hdr.base.address );

                end

                //////////////////////// C1 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Write Request *****************/
                if (! reset && c1Tx.valid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%s\t%x\t%s %x\t%x\n",
                            $time,
                            print_channel(c1Tx.hdr.base.vc_sel),
                            c1Tx.hdr.base.cl_len,
                            (c1Tx.hdr.base.sop ? "S" : "x"),
                            print_c1_reqtype(c1Tx.hdr.base.req_type),
                            c1Tx.hdr.base.mdata,
                            (c1Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            c1Tx.hdr.base.address,
                            c1Tx.data);
                end

                //////////////////////// C2 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MMIO Read Response *****************/
                if (! reset && c2Tx.mmioRdValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\tMMIORdRsp\t%x\t%x\n",
                            $time,
                            c2Tx.hdr.tid,
                            c2Tx.data);
                end

                //////////////////////// C0 RX CHANNEL TRANSACTIONS //////////////////////////
                /******************* MEM -> AFU Read Response *****************/
                if (! reset && c0Rx.rspValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%s\t%x\t%x\n",
                            $time,
                            print_channel(c0Rx.hdr.vc_used),
                            c0Rx.hdr.cl_num,
                            ((c0Rx.hdr.cl_num == 0) ? "S" :
                               cci_mpf_c0Rx_isEOP(c0Rx) ? "E" : "x"),
                            print_c0_resptype(c0Rx.hdr.resp_type),
                            c0Rx.hdr.mdata,
                            c0Rx.data);
                end

                /****************** MEM -> AFU Write Response *****************/
                if (! reset && c1Rx.rspValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%s\t%x\n",
                            $time,
                            print_channel(c1Rx.hdr.vc_used),
                            c1Rx.hdr.cl_num,
                            (c1Rx.hdr.format ? "F" : "x"),
                            print_c1_resptype(c1Rx.hdr.resp_type),
                            c1Rx.hdr.mdata);
                end

                /******************* SW -> AFU Config Write *******************/
                if (! reset && c0Rx.mmioWrValid)
                begin
                    t_cci_c0_ReqMmioHdr mmio_hdr;
                    mmio_hdr = t_cci_c0_ReqMmioHdr'(c0Rx.hdr);

                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\tMMIOWrReq\t%x\t%d bytes\t%x\t%x\n",
                            $time,
                            mmio_hdr.tid,
                            csr_len(mmio_hdr.length),
                            mmio_hdr.address,
                            c0Rx.data[63:0]);
                end

                /******************* SW -> AFU Config Read *******************/
                if (! reset && c0Rx.mmioRdValid)
                begin
                    t_cci_c0_ReqMmioHdr mmio_hdr;
                    mmio_hdr = t_cci_c0_ReqMmioHdr'(c0Rx.hdr);

                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\tMMIORdReq\t%x\t%d bytes\t%x\n",
                            $time,
                            mmio_hdr.tid,
                            csr_len(mmio_hdr.length),
                            mmio_hdr.address);
                end
            end
        end
    end

`endif //  `ifndef CCI_MPF_IF_DBG_VH
