// --------------------------------------------------------------------
// ASE generics (SystemVerilog header file) 
// Author: Rahul R Sharma <rahul.r.sharma@intel.com>
//         Intel Corporation
// 
// Description:
// This file contains definitions and parameters for the DPI
// module. The intent of this file is that the user should not modify
// the DPI source files. **Only** this header file must be modified if
// any DPI parameters need to be changed.
//
// ----------------------------------------------------------------------
// NOTE: If SPL is included in design, CAFU = SPL + AFU(s)
// ----------------------------------------------------------------------

`ifndef _ASE_GLOBAL_
 `define _ASE_GLOBAL_

 `define GRAM_AUTO "no_rw_check"                         // defaults to auto
 `define GRAM_STYLE RAM_STYLE
 `define SYNC_RESET_POLARITY 0

// ---------------------------------------------------------------------
// CCI Transactions 
// ---------------------------------------------------------------------
// TX0 channel
 `define ASE_TX0_RDLINE       4'h4
// TX1 channel
 `define ASE_TX1_WRTHRU       4'h1
 `define ASE_TX1_WRLINE       4'h2
 `define ASE_TX1_WRFENCE      4'h5  // CCI 1.8 
 `define ASE_TX1_INTRVALID    4'h8  // CCI 1.8
// RX0 channel
 `define ASE_RX0_CSR_WRITE    4'h0
 `define ASE_RX0_WR_RESP      4'h1
 `define ASE_RX0_RD_RESP      4'h4
 `define ASE_RX0_INTR_CMPLT   4'h8  // CCI 1.8
 `define ASE_RX0_UMSG         4'hf  // CCI 1.8
// RX1 channel
 `define ASE_RX1_WR_RESP      4'h1
 `define ASE_RX1_INTR_CMPLT   4'h8  // CCI 1.8


// ---------------------------------------------------------------------
// CCI header specifications
// ---------------------------------------------------------------------
 `define CCI_TX0_HDR_WIDTH          61
 `define CCI_TX1_HDR_WIDTH          61
 `define CCI_DATA_WIDTH             512
 `define CCI_RX0_HDR_WIDTH          18
 `define CCI_RX1_HDR_WIDTH          18
 `define CCI_CSR_WIDTH              32
 

// ---------------------------------------------------------------------
// Duration settings
// ---------------------------------------------------------------------
// `define CLK_TIME             2
// `define RST_TIME             10
// `define ASE_ENDTASK_DELAY    5

// ---------------------------------------------------------------------
// Dump file settings
// ---------------------------------------------------------------------
 // `define VCD_DUMP_FILE        "wavedump.vcd"

// ---------------------------------------------------------------------
// Dword align setting for CAFU
// NLB csr_writes are Dword aligned (shifted right by 2 buts before applying
// If your CAFU uses a similar shift, DO NOT edit this setting.
// ----------------------------------------------------------------------
 `define CAFU_ADDR_SHIFT        >> 2

// ----------------------------------------------------------------------
// FIFO depth bit-width
// Enter 'n' here, where n = log_2(FIFO_DEPTH) & n is an integer
// ----------------------------------------------------------------------
 `define ASE_FIFO_DEPTH_NUMBITS  6
 // `define ASE_FIFO_FALL_THRU   1
 // `define ASE_FIFO_REG_OUT     0

// ----------------------------------------------------------------------
// Inactivity kill-switch
// ----------------------------------------------------------------------
 `define INACTIVITY_KILL_ENABLE   1
 `define INACTIVITY_TIMEOUT       5000

// ----------------------------------------------------------------------
// Randomization features
// Select shuffle_fifo vs. fifo 
// ----------------------------------------------------------------------
//`define ASE_RANDOMIZE_TRANSACTIONS 
 `ifdef ASE_RANDOMIZE_TRANSACTIONS
  `define ASE_FORWARDING_PATH shuffle_fifo
 `else
  `define ASE_FORWARDING_PATH fifo
 `endif


// ----------------------------------------------------------------------
// SIMKILL_ON_UNDEFINED: A switch to kill simulation if on a valid
// signal, 'X' or 'Z' is not allowed, gracious closedown on same
// ----------------------------------------------------------------------
`define CCI_SIMKILL_ON_ILLEGAL_BITS  0
`define VLOG_UNDEF                   1'bx
`define VLOG_HIIMP                   1'bz


// ----------------------------------------------------------------------
// Print in Color
// ----------------------------------------------------------------------
// Error in RED color
`define BEGIN_RED_FONTCOLOR   $display("\033[1;31m");
`define END_RED_FONTCOLOR     $display("\033[1;m");

// Info in GREEN color
`define BEGIN_GREEN_FONTCOLOR $display("\033[32;1m");
`define END_GREEN_FONTCOLOR   $display("\033[0m");


`endif //  `ifndef _ASE_GLOBAL_



