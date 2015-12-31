//
// MPF's view of CCI expressed as a SystemVerilog interface.
//

`ifndef CCI_MPF_IF_VH
`define CCI_MPF_IF_VH

import cci_mpf_if_pkg::*;

`ifdef USE_PLATFORM_CCI_S
import ccis_if_pkg::*;
`endif

`ifdef USE_PLATFORM_CCI_P
import ccip_if_pkg::*;
`endif

// Global log file handle
int cci_mpf_if_log_fd = -1;

interface cci_mpf_if
  #(
    parameter ENABLE_LOG = 0,        // Log events for this instance?
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 14
    )
   (
    input logic clk
    );

    // Reset flows from QLP to AFU
    logic              reset_n;

    // Requests to QLP.  All objects are outputs flowing toward QLP except
    // the almost full ports, which provide flow control.
    t_if_cci_mpf_c0_Tx c0Tx;
    logic              c0TxAlmFull;

    t_if_cci_mpf_c1_Tx c1Tx;
    logic              c1TxAlmFull;

    // Responses from QLP.  All objects are inputs from the QLP and flow
    // toward the AFU.  There is no flow control.  The AFU must be prepared
    // to receive responses for all in-flight requests.
    t_if_cci_c0_Rx     c0Rx;
    t_if_cci_c1_Rx     c1Rx;

    // Port directions for connections in the direction of the QLP (platform)
    modport to_qlp
      (
       input  reset_n,

       output c0Tx,
       input  c0TxAlmFull,

       output c1Tx,
       input  c1TxAlmFull,

       input  c0Rx,
       input  c1Rx
       );

    // Port directions for connections in the direction of the AFU (user code)
    modport to_afu
      (
       output reset_n,

       input  c0Tx,
       output c0TxAlmFull,

       input  c1Tx,
       output c1TxAlmFull,

       output c0Rx,
       output c1Rx
       );


    // ====================================================================
    //
    // Snoop equivalents of the above interfaces: all the inputs and none
    // of the outputs.
    //
    // ====================================================================

    modport to_qlp_snoop
      (
       input  reset_n,

       input  c0TxAlmFull,
       input  c1TxAlmFull,

       input  c0Rx,
       input  c1Rx
       );

    modport to_afu_snoop
      (
       input  reset_n,

       input  c0Tx,
       input  c1Tx
       );


`ifdef CCI_SIMULATION
    // ====================================================================
    //
    //   Debugging
    //
    // ====================================================================

    int log_fd;

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

    initial
    begin : logger_proc
        if (cci_mpf_if_log_fd == -1)
        begin
            cci_mpf_if_log_fd = $fopen("cci_mpf_if.tsv", "w");
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
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%s\t%x\t%s %x\n",
                            $time,
                            print_channel(0 /*c0Tx.hdr.vc*/),
                            print_reqtype(c0Tx.hdr.base.req_type),
                            c0Tx.hdr.base.mdata,
                            (c0Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            (c0Tx.hdr.ext.addrIsVirtual ?
                                getReqVAddrMPF(c0Tx.hdr) :
                                c0Tx.hdr.base.address) );

                end

                //////////////////////// C1 TX CHANNEL TRANSACTIONS //////////////////////////
                /******************* AFU -> MEM Write Request *****************/
                if (reset_n && c1Tx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%s\t%x\t%s %x\t%x\n",
                            $time,
                            print_channel(0 /*c1Tx.hdr.vc*/),
                            print_reqtype(c1Tx.hdr.base.req_type),
                            c1Tx.hdr.base.mdata,
                            (c1Tx.hdr.ext.addrIsVirtual ? "V" : "P"),
                            (c1Tx.hdr.ext.addrIsVirtual ?
                                getReqVAddrMPF(c1Tx.hdr) :
                                c1Tx.hdr.base.address),
                            c1Tx.data);
                end

                //////////////////////// C0 RX CHANNEL TRANSACTIONS //////////////////////////
                /******************* MEM -> AFU Read Response *****************/
                if (reset_n && c0Rx.rdValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%s\t%x\t%x\n",
                            $time,
                            print_channel(0 /*c0Rx.hdr.vc*/),
                            print_resptype(c0Rx.hdr.resp_type),
                            c0Rx.hdr.mdata,
                            c0Rx.data);
                end

                /****************** MEM -> AFU Write Response *****************/
                if (reset_n && c0Rx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%s\t%x\n",
                            $time,
                            print_channel(0 /*c0Rx.hdr.vc*/),
                            print_resptype(c0Rx.hdr.resp_type),
                            c0Rx.hdr.mdata);
                end

                if (reset_n && c1Rx.wrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%m:\t%t\t%s\t%s\t%x\n",
                            $time,
                            print_channel(0 /*c1Rx.hdr.vc*/),
                            print_resptype(c1Rx.hdr.resp_type),
                            c1Rx.hdr.mdata);
                end

`ifdef BOO
                /////////////////////// CONFIG CHANNEL TRANSACTIONS //////////////////////////
                /******************* SW -> AFU Config Write *******************/
                if (C0RxMMIOWrValid)
                begin
                    $fwrite(cci_mpf_if_log_fd, "%t\tMMIOWrReq\t%x\t%d bytes\t%s\n",
                            $time,
                            C0RxMMIOHdr.index,
                            4^(1 + C0RxMMIOHdr.len),
                            csr_data(4^(1 + C0RxMMIOHdr.len), C0RxData) );
                end
`endif

            end
        end
    end
`endif //  `ifdef ENABLE_CCI_MPF_DEBUG


endinterface

`endif //  CCI_MPF_IF_VH
