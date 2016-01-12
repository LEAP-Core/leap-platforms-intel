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
    function string print_reqtype (logic [3:0] req);
        case (req)
            eREQ_WRLINE_I: return "WrLine_I ";
            eREQ_WRLINE_M: return "WrLine_M ";
            eREQ_WRFENCE:  return "WrFence  ";
            eREQ_RDLINE_S: return "RdLine_S ";
            eREQ_RDLINE_I: return "RdLine_I ";
            eREQ_INTR:     return "IntrReq  ";
            default:       return "* ERROR *";
        endcase
    endfunction

    // Print resp type
    function string print_resptype (logic [3:0] resp);
        case (resp)
            eRSP_WRLINE: return "WrResp   ";
            eRSP_RDLINE: return "RdResp   ";
            eRSP_INTR:   return "IntrResp ";
            eRSP_UMSG:   return "UmsgResp ";
            default:     return "* ERROR *";
        endcase
    endfunction

    // Print CSR data
    function string csr_data(int num_bytes, t_cci_cldata rx0_data);
        string str_4;
        string str_8;
        string str_64;

        begin
          case (num_bytes)
            4 :
            begin
                str_4.hextoa(rx0_data[31:0]);
                return str_4;
            end

            8 :
            begin
                str_8.hextoa(rx0_data[63:0]);
                return str_8;
            end

            64 :
            begin
                str_64.hextoa(rx0_data[511:0]);
                return str_64;
            end
          endcase
        end
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
                if (reset_n && c0Tx.rdValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\t%s %x\n",
                            $time,
`ifdef USE_PLATFORM_CCIS
                            print_channel(0),
                            0,
`else
                            print_channel(c0Tx.hdr.base.vc_sel),
                            c0Tx.hdr.base.cl_num,
`endif
                            print_reqtype(c0Tx.hdr.base.req_type),
                            c0Tx.hdr.base.mdata,
                            (c0Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            (c0Tx.hdr.ext.addrIsVirtual ?
                                cci_mpf_getReqVAddr(c0Tx.hdr) :
                                c0Tx.hdr.base.address) );

                end

                //////////////////////// C1 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Write Request *****************/
                if (reset_n && c1Tx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\t%s %x\t%x\n",
                            $time,
`ifdef USE_PLATFORM_CCIS
                            print_channel(0),
                            0,
`else
                            print_channel(c1Tx.hdr.base.vc_sel),
                            c1Tx.hdr.base.cl_num,
`endif
                            print_reqtype(c1Tx.hdr.base.req_type),
                            c1Tx.hdr.base.mdata,
                            (c1Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            (c1Tx.hdr.ext.addrIsVirtual ?
                                cci_mpf_getReqVAddr(c1Tx.hdr) :
                                c1Tx.hdr.base.address),
                            c1Tx.data);
                end

                //////////////////////// C0 RX CHANNEL TRANSACTIONS //////////////////////////
                /******************* MEM -> AFU Read Response *****************/
                if (reset_n && c0Rx.rdValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\t%x\n",
                            $time,
`ifdef USE_PLATFORM_CCIS
                            print_channel(0),
                            0,
`else
                            print_channel(c0Rx.hdr.vc_used),
                            c0Rx.hdr.cl_num,
`endif
                            print_resptype(c0Rx.hdr.resp_type),
                            c0Rx.hdr.mdata,
                            c0Rx.data);
                end

                /****************** MEM -> AFU Write Response *****************/
                if (reset_n && c0Rx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\n",
                            $time,
`ifdef USE_PLATFORM_CCIS
                            print_channel(0),
                            0,
`else
                            print_channel(c0Rx.hdr.vc_used),
                            c0Rx.hdr.cl_num,
`endif
                            print_resptype(c0Rx.hdr.resp_type),
                            c0Rx.hdr.mdata);
                end

                if (reset_n && c1Rx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%0d\t%s\t%x\n",
                            $time,
`ifdef USE_PLATFORM_CCIS
                            print_channel(0),
                            0,
`else
                            print_channel(c1Rx.hdr.vc_used),
                            c1Rx.hdr.cl_num,
`endif
                            print_resptype(c1Rx.hdr.resp_type),
                            c1Rx.hdr.mdata);
                end

`ifdef FIXME
                /******************* SW -> AFU Config Write *******************/
                if (reset_n && c0Rx.mmioWrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%t\tMMIOWrReq\t%x\t%d bytes\t%s\n",
                            $time,
                            c0RxMMIOHdr.index,
                            4^(1 + C0RxMMIOHdr.len),
                            csr_data(4^(1 + C0RxMMIOHdr.len), C0RxData) );
                end
`endif

            end
        end
    end

`endif //  `ifndef CCI_MPF_IF_DBG_VH
