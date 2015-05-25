`ifndef SYS_CFG_PKG_SV              //------------------------------------------------------------------------------   
                                    //                   Hardware/Synthesis Configuration
    `define SYS_CFG_PKG_SV          //------------------------------------------------------------------------------  
	 `define EXCEPTION_IVYTOWN
	 `define BITSTREAM_ID 'd14566
    `define CA_ONLY                 // Cache Agent Only.  If neither CA_ONLY nor HA_ONLY, then it's CA+HA
//  `define HA_ONLY                 // Home Agent Only.   If neither CA_ONLY nor HA_ONLY, then it's CA+HA
//  `define TRACER                  // Tracer Capture Logic (restricted to CA_ONLY + DDR + no cci)
//  `define DEBUG_CCI_TOP           // Add cci debug signals
    `define DEBUG                   // Add internal signals and logic analyzer for debug (chipscope or singaltaps)
//  `define CRC_INJECT              // Add CRC injection logic
//  `define RANDOM_CRC              // Use randomn CRC injection; otherwise periodic CRC injection
                                    //------------------------------------------------------------------------------   
                                    //               Tool and Misc Configurations (rarely modified)
                                    //------------------------------------------------------------------------------   
    `define USE_CCI_STD             // intantiate NLB (native loopback) RTL for CA
    `define VENDOR_ALTERA           // Use Altera FPGA
    `define TOOL_QUARTUS            // Use Altera Quartus Tools     
//  `define CSR_OPTIMIZATION        // Remove unused CSRs
    `define USE_QUADQ               // Enable Quad Queue FIFO -- allows 2R 2W per clock, but hurts timing
    `define LOCAL_WAY     0         // Tag associativety (in log2) - Min value = 1, Max value = 2
    `define REMOTE_WAY    1         // Tag associativety (in log2) - Min value = 1, Max value = 2
    `define SNP_WAY       0         // Snoop filter associativity (in log2) - Min value = 1, Max value = 3
`endif
 
 
