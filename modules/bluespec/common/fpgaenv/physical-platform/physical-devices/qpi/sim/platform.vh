`ifndef _PLATFORM_VH_
 `define _PLATFORM_VH_

/*
 * Simulation Timescale 
 */ 
 `timescale 10ns/10ns


/*
 * ASE Channel randomization features
 */
`define ASE_RANDOMIZE_TRANSACTIONS 


/*
 * Enable System Release 4.0 features
 * SR 4.x => Check if DSM transactions lie in 0x0000 - 0xFFFF
 * SR 3.x => Check if DSM transactions lie in 0x000  - 0xFFF 
 * 
 * Comment the following line to disable SR 4.x checks and enable SR 3.x checks
 */ 
`define CCI_RULE_CHECK_SR_4_0

// AFU Address range settings
`ifdef CCI_RULE_CHECK_SR_4_0
  parameter CCI_AFU_LOW_OFFSET  = 14'h0900 / 4;
//  parameter CCI_AFU_HIGH_OFFSET = 14'h0FFC / 4;
`else
  parameter CCI_AFU_LOW_OFFSET  = 14'h1000 / 4;
//  parameter CCI_AFU_HIGH_OFFSET = 14'hFFFC / 4;
`endif


/*
 * Select the platform to test
 * Options: GENERIC | QPI_JKT
 * 
 * ## WARNING ## Select only one of these
 * 
 * GENERIC = Generic platform (non-realistic functional test)
 * QPI_JKT = QPI Jaketown platform
 * 
 */ 
 `define GENERIC


/*
 * QPI-FPGA CA private memory (CA-PCM) specifications
 * - ENABLE_CACHING_AGENT_PRIVATE_MEMORY enables private memory 
 *   This is an extra memory block that is inaccessible to the SW_APP
 * - CAPCM_NUM_CACHE_LINES is the number of cache-lines in CA-PCM
 *   One cache line is 64-bytes 
 */
// parameter ENABLE_CACHING_AGENT_PRIVATE_MEMORY = 1;
// parameter longint CAPCM_NUM_BYTES                     = 32*1024*1024*1024;      
// *FIXME*: Clean up this block

/*
 * Relevant CSRs that control CCI or AFU behaviour
 */
parameter CCI_RESET_CTRL_OFFSET = 12'h280 / 4;
parameter CCI_RESET_CTRL_BITLOC = 24;

/*
 * CCI Source address decoder (SAD)
 * ----------------------------------------------------------------------
 * Instructions to user => Select one of the following configs
 * Variable Encoding:
 * ASE_{Over/Under}_<PrivateMemory>_{Over/Under}_<SystemMemory>_SAD
 * 
 */ 
// *FIXME*

/*
 * Platform Specific parameters
 * ----------------------------- 
 * INITIAL_SYSTEM_RESET_DURATION = Duration of initial system reset before system is up and running
 * CLK_TIME                      = Clock cycle timescale
 * LP_INITDONE_READINESS_LATENCY = Amount of time LP takes to be ready after reset is released 
 */

/* QPI Jaketown */
 `ifdef QPI_JKT
  `define INITIAL_SYSTEM_RESET_DURATION         20
  `define CLK_32UI_TIME                         5ns
  `define CLK_16UI_TIME                         2.5ns
  `define LP_INITDONE_READINESS_LATENCY         5

/* Generic, non-realistic, functional only simulation */ 
 `elsif GENERIC
  `define INITIAL_SYSTEM_RESET_DURATION         20
  `define CLK_32UI_TIME                         5ns
  `define CLK_16UI_TIME                         2.5ns
  `define LP_INITDONE_READINESS_LATENCY         5

 `endif




/*
 * TEST: Latency ranges
 * Coded as a Min,Max tuple
 * -------------------------------------------------------
 * CSR_WR_LATRANGE : CSR Write latency range
 * RDLINE_LATRANGE : ReadLine turnaround time
 * WRLINE_LATRANGE : WriteLine turnaround time
 * UMSG_LATRANGE   : UMsg latency
 * INTR_LATRANGE   : Interrupt turnaround time
 * 
 * LAT_UNDEFINED   : Undefined latency
 * 
 */ 
`define CSR_WR_LATRANGE 5,10
`define RDLINE_LATRANGE 8,16
`define WRLINE_LATRANGE 4,7
`define WRTHRU_LATRANGE 4,7
`define UMSG_LATRANGE   6,12
`define INTR_LATRANGE   10,15

`define LAT_UNDEFINED   5

`endif
