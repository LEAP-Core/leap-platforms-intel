`define _PLATFORM_VH_
`ifdef _PLATFORM_VH_

/*
 * Simulation Timescale 
 */ 
// `timescale 10ps/10ps

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
parameter ENABLE_CACHING_AGENT_PRIVATE_MEMORY = 0;
parameter longint CAPCM_NUM_BYTES                     = 1*1024*1024*1024;      
parameter longint CAPCM_NUM_CACHE_LINES               = CAPCM_NUM_BYTES >> 6;  // 64 bytes = 1 cacheline
parameter longint CAPCM_CL_ADDR_WIDTH                 = $clog2(CAPCM_NUM_CACHE_LINES);

/*
 * Relevant CSRs that control CCI or AFU behaviour
 */
parameter CCI_RESET_CTRL_ADDR = 12'h280;
parameter CCI_RESET_CTRL_BITLOC = 24;


/*
 * Enable CCI 2.1 Features
 * - Enables UMsg, Interrupts
 * - These switches will be deprecated going forward, and will be part of 
 * default features 
 */
// `define ENABLE_CCI_UMSG_IF            // Enables UMSG in the system
// `define ENABLE_CCI_INTR_IF            // Enables Interrupts in the system


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
  `define CLK_TIME                              2
  `define LP_INITDONE_READINESS_LATENCY         5

/* Generic, non-realistic, functional only simulation */ 
 `elsif GENERIC
  `define INITIAL_SYSTEM_RESET_DURATION         20
  `define CLK_TIME                              2
  `define LP_INITDONE_READINESS_LATENCY         5

 `endif

`endif
