/* ****************************************************************************
 * Copyright (c) 2011-2015, Intel Corporation
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * * Redistributions of source code must retain the above copyright notice,
 * this list of conditions and the following disclaimer.
 * * Redistributions in binary form must reproduce the above copyright notice,
 * this list of conditions and the following disclaimer in the documentation
 * and/or other materials provided with the distribution.
 * * Neither the name of Intel Corporation nor the names of its contributors
 * may be used to endorse or promote products derived from this software
 * without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 * **************************************************************************
 * 
 * Module Info:
 * Language   : System{Verilog} | C/C++
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 * 
 * ASE generics (SystemVerilog header file) 
 * 
 * Description:
 * This file contains definitions and parameters for the DPI
 * module. The intent of this file is that the user should not modify
 * the DPI source files. **Only** this header file must be modified if
 * any DPI parameters need to be changed.
 *
 */

`ifndef _ASE_GLOBAL_VH_
 `define _ASE_GLOBAL_VH_

 `define GRAM_AUTO "no_rw_check"                         // defaults to auto
 `define GRAM_STYLE RAM_STYLE
 `define SYNC_RESET_POLARITY 0

/*
 * CCI Transactions 
 */
// TX0 channel
 `define ASE_TX0_RDLINE       4'h4  // To be deprecated
 `define ASE_TX0_RDLINE_S     4'h4
 `define ASE_TX0_RDLINE_I     4'h6
 `define ASE_TX0_RDLINE_O     4'h7
// TX1 channel
 `define ASE_TX1_WRTHRU       4'h1
 `define ASE_TX1_WRLINE       4'h2
 `define ASE_TX1_WRFENCE      4'h5  
 `define ASE_TX1_INTRVALID    4'h8  // Implemented as hidden feature
// RX0 channel
 `define ASE_RX0_CSR_WRITE    4'h0
 `define ASE_RX0_WR_RESP      4'h1
 `define ASE_RX0_RD_RESP      4'h4
 `define ASE_RX0_INTR_CMPLT   4'h8  // Implemented as hidden feature
 `define ASE_RX0_UMSG         4'hF  
// RX1 channel
 `define ASE_RX1_WR_RESP      4'h1
 `define ASE_RX1_INTR_CMPLT   4'h8  // Implemented as hidden feature


/*
 * CCI specifications
 */
 `define CCI_TX_HDR_WIDTH           61
 `define CCI_RX_HDR_WIDTH           18
 `define CCI_DATA_WIDTH             512
 `define CCI_CSR_WIDTH              32
 `define CCI_META_WIDTH             14
 `define CCI_UMSG_BITINDEX          12

/*
 * SPL specifications
 */
 `define SPL_TX_HDR_WIDTH           99
 `define SPL_RX_HDR_WIDTH           18
 `define SPL_DATA_WIDTH             512
 `define SPL_CSR_WIDTH              32


/*
 * TX header deconstruction
 */
// SPL (CCI-extended additions)
 `define TX_HDR_NUMCL_BITRANGE      98:93             
 `define TX_HDR_CLADDR_BITRANGE     92:67         
 `define TX_HDR_PV_BIT              66
// CCI only
 `define TX_META_TYPERANGE          55:52   
 `define TX_MDATA_BITRANGE          13:0
 `define TX_CLADDR_BITRANGE         45:14

/*
 * RX header deconstruction
 */ 
// RX header (SPL/CCI common response)
 `define RX_META_TYPERANGE          17:14
 `define RX_MDATA_BITRANGE          13:0
 `define RX_CSR_BITRANGE            13:0
 `define RX_CSR_DATARANGE           31:0


/*
 * FIFO depth bit-width
 * Enter 'n' here, where n = log_2(FIFO_DEPTH) & n is an integer
 */
 `define ASE_FIFO_DEPTH_NUMBITS  8


/*
 * SIMKILL_ON_UNDEFINED: A switch to kill simulation if on a valid
 * signal, 'X' or 'Z' is not allowed, gracious closedown on same
 */
`define VLOG_UNDEF                   1'bx
`define VLOG_HIIMP                   1'bz


/*
 * Latency Scoreboard generics
 */
// Number of transactions in latency scoreboard
`define LATBUF_NUM_TRANSACTIONS     8
// Radix of latency scoreboard radix
`define LATBUF_COUNT_WIDTH          ($clog2(`LATBUF_NUM_TRANSACTIONS) + 1)
// ASE_fifo full threshold inside latency scoreboard
`define LATBUF_FULL_THRESHOLD       (`LATBUF_NUM_TRANSACTIONS - 5)
// Radix of ASE_fifo (subcomponent in latency scoreboard)
`define LATBUF_DEPTH_BASE2          3  


/*
 * Print in Color
 */
// Error in RED color
`define BEGIN_RED_FONTCOLOR   $display("\033[1;31m");
`define END_RED_FONTCOLOR     $display("\033[1;m");

// Info in GREEN color
`define BEGIN_GREEN_FONTCOLOR $display("\033[32;1m");
`define END_GREEN_FONTCOLOR   $display("\033[0m");

// Warnings/ASEDBGDUMP in YELLOW color
`define BEGIN_YELLOW_FONTCOLOR $display("\033[0;33m"); // "\[\033[0;33m\]"
`define END_YELLOW_FONTCOLOR   $display("\033[0m");


/*
 * CCI Transaction packet
 */
typedef struct {
   longint     meta;
   longint     qword[8];
   int 	       cfgvalid;
   int 	       wrvalid;
   int 	       rdvalid;
   int 	       intrvalid;
   int 	       umsgvalid; 	       
   } cci_pkt;
		 

/*
 * ASE config structure
 * This will reflect ase.cfg
 */
typedef struct {
   int 	       enable_timeout;
   int 	       enable_capcm;
   int 	       memmap_sad_setting;
   int 	       enable_umsg;
   int 	       num_umsg_log2;
   int 	       enable_intr;
   int 	       enable_ccirules;
   int 	       enable_bufferinfo;
   int 	       enable_asedbgdump;
   int 	       enable_cl_view;
} ase_cfg_t;
ase_cfg_t cfg;


/*
 * FUNCTION: Unpack qwords[0:7] to data vector
 */
function logic [`CCI_DATA_WIDTH-1:0] unpack_ccipkt_to_vector (input cci_pkt pkt);
   logic [`CCI_DATA_WIDTH-1:0] ret;
   int 			       i;
   begin
      ret[  63:00  ] = pkt.qword[0] ;
      ret[ 127:64  ] = pkt.qword[1] ;
      ret[ 191:128 ] = pkt.qword[2] ;
      ret[ 255:192 ] = pkt.qword[3] ;
      ret[ 319:256 ] = pkt.qword[4] ;
      ret[ 383:320 ] = pkt.qword[5] ;
      ret[ 447:384 ] = pkt.qword[6] ;
      ret[ 511:448 ] = pkt.qword[7] ;
      return ret;
   end
endfunction

/*
 * FUNCTION: Pack data vector into qwords[0:7]
 */
function automatic void pack_vector_to_ccipkt (input [511:0] vec, ref cci_pkt pkt);
   begin
      pkt.qword[0] =  vec[  63:00 ];
      pkt.qword[1] =  vec[ 127:64  ];
      pkt.qword[2] =  vec[ 191:128 ];
      pkt.qword[3] =  vec[ 255:192 ];
      pkt.qword[4] =  vec[ 319:256 ];
      pkt.qword[5] =  vec[ 383:320 ];
      pkt.qword[6] =  vec[ 447:384 ];
      pkt.qword[7] =  vec[ 511:448 ];
   end
endfunction


`endif //  `ifndef _ASE_GLOBAL_VH_

