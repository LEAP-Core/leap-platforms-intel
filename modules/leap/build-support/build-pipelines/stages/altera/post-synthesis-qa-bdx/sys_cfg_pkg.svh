`ifndef SYS_CFG_PKG_SV              //------------------------------------------------------------------------------   
                                    //                   Hardware/Synthesis Configuration
    `define SYS_CFG_PKG_SV          //------------------------------------------------------------------------------  
	 `define BITSTREAM_ID 'h0
	 `define BITSTREAM_ID_64b 'h0500_0000_0000_0000
    `define CA_ONLY                 // Cache Agent Only.  If neither CA_ONLY nor HA_ONLY, then it's CA+HA
    `define NUM_AFUS 4'h1
    `define INSTANTIATE_QPI
    `define INSTANTIATE_PCIE_0
    `define INSTANTIATE_PCIE_1
//  `define INSTANTIATE_HSSI
//  `define CA8G                    // Cache Agent 8G Timing
//  `define HA_ONLY                 // Home Agent Only.   If neither CA_ONLY nor HA_ONLY, then it's CA+HA
//  `define TRACER                  // Tracer Capture Logic (restricted to CA_ONLY + DDR + no cci)
//  `define DEBUG_CCI_TOP           // Add cci debug signals
//  `define DEBUG                   // Add internal signals and logic analyzer for debug (chipscope or singaltaps)
                                    //------------------------------------------------------------------------------   
                                    //               Tool and Misc Configurations (rarely modified)
                                    //------------------------------------------------------------------------------   
    `define USE_CCI_STD                 // intantiate NLB (native loopback) RTL for CA
    `define VENDOR_ALTERA           // Use Altera FPGA
    `define TOOL_QUARTUS            // Use Altera Quartus Tools     
    `define CSR_OPTIMIZATION        // Remove unused CSRs
    `define USE_QUADQ               // Enable Quad Queue FIFO -- allows 2R 2W per clock, but hurts timing
    `define LOCAL_WAY     0         // Tag associativety (in log2) - Min value = 1, Max value = 2
    `define REMOTE_WAY    0         // Tag associativety (in log2) - Min value = 1, Max value = 2
    `define SNP_WAY       0         // Snoop filter associativity (in log2) - Min value = 1, Max value = 3
    `define FPGA_NODEID 5'h1
    `define CPU_NODEID 5'h4
    `define INTLV_MODE 3'h0 
`endif
 
 
