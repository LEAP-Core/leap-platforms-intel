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
 * Module Info: CCI Emulation top-level - SystemVerilog Module
 * Language   : System{Verilog}
 * Owner      : Rahul R Sharma
 *              rahul.r.sharma@intel.com
 *              Intel Corporation
 *
 * MAJOR UPGRADES:
 * - RRS: Wed Aug 10 22:17:28 PDT 2011
 *   Completed FIFO'ing all channels in all directions
 * - RRS: Tue Jun 17 16:46:06 PDT 2014
 *   Started cleaning up code to add latency model
 *   - Protect existing code
 *   - Step-by-step modify channels
 *   Connect up new transactions CCI 1.8
 *
 */

`include "ase_global.vh"
`include "platform.vh"

// CCI to Memory translator module
module cci_emulator();

   /*
    * DPI import/export functions
    */
   // ASE Initialize function
   import "DPI-C" context task ase_init();
   // Indication that ASE is ready
   // import "DPI-C" context task ase_ready();
   import "DPI-C" function void ase_ready();
   // Buffer replicator daemon
   import "DPI-C" context task buffer_replicator();

   // ASE config data exchange (read from ase.cfg)
   export "DPI-C" task ase_config_dex;

   // CSR write listener daemon
   import "DPI-C" context task csr_write_listener();
   // CSR write initiator (SV)
   export "DPI-C" task csr_write_init;
   // CSR write completed
   import "DPI-C" function void csr_write_completed();

   // Umsg listener darmon
   import "DPI-C" context task umsg_listener();
   // UMSG init
   export "DPI-C" task umsg_init;
   // Umsg completed
   import "DPI-C" function void umsg_completed();   
   
   // CAPCM initilize
   import "DPI-C" context task capcm_init();
   // CAPCM destroy
   // import "DPI-C" context task capcm_deinit();

   // Start simulation structures teardown
   import "DPI-C" context task start_simkill_countdown();
   // Signal to kill simulation
   export "DPI-C" task simkill;

   // Data exchange for CSR write
   import "DPI-C" function void csr_write_dex(inout cci_pkt foo);
   // Data exchange for UMSG
   import "DPI-C" function void umsg_dex(inout cci_pkt foo);
   // Data exchange for READ system memory line
   import "DPI-C" function void rd_memline_dex(inout cci_pkt foo, int cl_addr, int mdata );
   // Data exchange for READ CAPCM line
   // import "DPI-C" function void rd_capcmline_dex(inout cci_pkt foo, int cl_addr, int mdata );
   // Data exchange for WRITE system memory line
   import "DPI-C" function void wr_memline_dex(inout cci_pkt foo, int cl_addr, int mdata, bit [511:0] wr_data );
   // Data exchange for WRITE CAPCM line
   // import "DPI-C" function void wr_capcmline_dex(inout cci_pkt foo, int cl_addr, int mdata, bit [511:0] wr_data );
   // Software controlled process - run clocks
   export "DPI-C" task run_clocks;


   /*
    * Declare packets for each channel
    */
   cci_pkt rx0_pkt, rx1_pkt;
   logic rx0_active, rx1_active;
   logic rx_free;
   integer test_ret;
   
   assign rx_free = ( (rx0_active == 1'b0)||(rx1_active == 1'b0) ) ? 1'b1 : 1'b0;

   /*
    * FUNCTION: Find a free return path
    */
   function automatic int find_free_rx_channel();
      int ch = 7;
      begin
	 if ((rx0_active == 1'b0) && (rx1_active == 1'b0)) begin
	    ch = $random % 2;
	 end
	 else if ((rx0_active == 1'b1) && (rx1_active == 1'b0)) begin
	    ch = 1;
	 end
	 else if ((rx0_active == 1'b0) && (rx1_active == 1'b1)) begin
	    ch = 0;
	 end
	 return ch;
      end
   endfunction


   /*
    * FUNCTION: Convert CAPCM_GB_SIZE to NUM_BYTES
    */
   function automatic longint conv_gbsize_to_num_bytes(int gb_size);
      begin
	 return (gb_size*1024*1024*1024);
      end
   endfunction


   /*
    * CCI signals declarations
    *
    *****************************************************************************
    *
    *                          -------------------
    *   tx0_header     ---61-->|                 |---18---> rx0_header
    *   tx0_valid      ------->|                 |---512--> rx0_data
    *   tx0_almostfull <-------|                 |--------> rx0_rdvalid
    *   tx1_header     ---61-->|      ASE        |--------> rx0_wrvalid
    *   tx1_data       --512-->|     BLOCK       |--------> rx0_cfgvalid
    *   tx1_valid      ------->|                 |--------> rx0_umsgvalid (TBD)
    *   tx1_almostfull <-------|                 |--------> rx0_intrvalid (TBD)
    *   tx1_intrvalid  ------->|                 |---18---> rx1_header
    *                          |                 |--------> rx1_intrvalid (TBD)
    *                          |                 |--------> rx1_wrvalid
    *                          |                 |--------> lp_initdone
    *                          |                 |--------> reset
    *                          |                 |--------> clk
    *                          -------------------
    *
    * ***************************************************************************
    *
    * MODIFIED:
    * - Thu Aug  4 10:54:49 PDT 2011: CCI 1.8 diagram
    *
    * **************************************************************************/

//   logic                          clk   ;                  // out
   logic 			  resetb ;                 // out
   logic 			  lp_initdone ;            // out
   logic [`CCI_TX_HDR_WIDTH-1:0]  tx_c0_header;            // in
   logic 			  tx_c0_rdvalid;           // in
   logic 			  tx_c0_almostfull;        // out
   logic [`CCI_TX_HDR_WIDTH-1:0]  tx_c1_header;            // in
   logic [`CCI_DATA_WIDTH-1:0] 	  tx_c1_data;              // in
   logic 			  tx_c1_wrvalid;           // in
   logic 			  tx_c1_almostfull;        // out
   logic [`CCI_RX_HDR_WIDTH-1:0]  rx_c0_header;            // out
   logic [`CCI_DATA_WIDTH-1:0] 	  rx_c0_data;              // out
   logic 			  rx_c0_rdvalid;           // out
   logic 			  rx_c0_wrvalid;           // out
   logic 			  rx_c0_cfgvalid;          // out
   logic [`CCI_RX_HDR_WIDTH-1:0]  rx_c1_header;            // out
   logic 			  rx_c1_wrvalid;           // out
   logic 			  rx_c0_umsgvalid;         // out
   logic 			  tx_c1_intrvalid;         // in
   logic 			  rx_c0_intrvalid;         // out
   logic 			  rx_c1_intrvalid;         // out


   // LP initdone & reset registered signals
   logic 			  lp_initdone_q;
   logic 			  resetb_q;
   logic 			  tx_c1_intrvalid_sel;

   // Derived clocks
   logic 			  clk_32ui = 0; // Normal 200 Mhz clock
   logic 			  clk_16ui; // Faster 400 Mhz clock
      

   /*
    * Clock process: Operates the CAFU clock
    */
   // 200 Mhz clock
   /*
   initial begin : clk32ui_proc
      begin
	 clk_32ui = 0;
	 forever begin
	    #`CLK_32UI_TIME;
	    clk_32ui = 1'b0;
	    #`CLK_32UI_TIME;
	    clk_32ui = 1'b1;
	 end
      end
   end

   // ASE clock
   assign clk = clk_32ui;
*/
   // 400 Mhz clock
   initial begin : clk16ui_proc
      begin
	 clk_16ui = 0;
	 forever begin
	    #`CLK_16UI_TIME;
	    clk_16ui = 1'b0;
	    #`CLK_16UI_TIME;
	    clk_16ui = 1'b1;
	 end
      end
   end
	 
   always @(posedge clk_16ui)
   begin
       clk_32ui <= ~clk_32ui;
   end
   
   /*
    * Reset management
    */
   logic 			  sys_reset_n;
   logic 			  sw_reset_n;
   logic 			  sw_reset_n_q;

   // Cycle counter for toggling sys_reset_n
   int 				  sys_rst_iter;


   /*
    * AFU reset - software & system resets
    */
   always @(posedge clk_32ui) begin
      if ((sys_reset_n == 1'b0) || (sw_reset_n == 1'b0)) begin
   	 resetb <= 1'b0;
      end
      else begin
   	 resetb <= 1'b1;
      end
   end


   /*
    * run_clocks : Run 'n' clocks
    * Software controlled event trigger for watching signals
    *
    */
   task run_clocks (int num_clks);
      int clk_iter;
      begin
	 for (clk_iter = 0; clk_iter < num_clks; clk_iter = clk_iter + 1) begin
	    @(posedge clk_32ui);
	 end
      end
   endtask


   /*
    * CSR Write infrastructure
    * - C:csr_write call calls SV:csr_write_init
    * - SV:csr_write_init sets a csr_write_enabled = 1
    * - When csr_write_enabled = 1, process tries to exchange data with
        C:csr_write_dex, gets written to RX0 path
    *
    */
   // Declare csr_write_enabled
   logic csr_write_enabled;

   // csr_write_init
   task csr_write_init(int flag);
      begin
	 csr_write_enabled = flag[0];
	 @(posedge clk_32ui);
      end
   endtask

   /* 
    * Umsg infrastructure
    * - C: umsg call calls SV:umsg_init
    * - SV:umsg_init sets a umsg_enabled = 1
    * - When umsg_enabled = 1, process tries to exchange data with
    *   C:umsg_dex, gets written to RX0 path /
    *
    */
   logic umsg_enabled;

   // Umsg_init
   task umsg_init(int flag);
      begin
	 umsg_enabled = flag[0];
	 @(posedge clk_32ui);
      end
   endtask

    
   /*
    * Config data exchange - Supplied by ase.cfg
    */ 
   task ase_config_dex(ase_cfg_t cfg_in);
      begin
	 cfg.enable_timeout    = cfg_in.enable_timeout   ;
	 cfg.enable_capcm      = cfg_in.enable_capcm     ;
	 cfg.memmap_sad_setting     = cfg_in.memmap_sad_setting    ;
	 cfg.enable_umsg       = cfg_in.enable_umsg      ;
	 cfg.num_umsg_log2     = cfg_in.num_umsg_log2    ;	 
	 cfg.enable_intr       = cfg_in.enable_intr      ;
	 cfg.enable_ccirules   = cfg_in.enable_ccirules  ;
	 cfg.enable_bufferinfo = cfg_in.enable_bufferinfo;
	 cfg.enable_cl_view    = cfg_in.enable_cl_view   ;
	 cfg.enable_asedbgdump = cfg_in.enable_asedbgdump;
      end
   endtask


   /*
    * Count Valid signals
    */
   int ase_rx0_cfgvalid_cnt;
   int ase_rx0_rdvalid_cnt;
   int ase_rx0_wrvalid_cnt;
   int ase_rx1_wrvalid_cnt;
   int ase_tx0_rdvalid_cnt;
   int ase_tx1_wrvalid_cnt; 

   int csr_write_enabled_cnt;
      
   always @(posedge clk_32ui) begin
      if (sys_reset_n == 1'b0) begin
	 ase_rx0_cfgvalid_cnt = 0;
	 ase_rx0_rdvalid_cnt = 0; 
	 ase_rx0_wrvalid_cnt = 0; 
	 ase_rx1_wrvalid_cnt = 0; 
	 ase_tx0_rdvalid_cnt = 0; 
	 ase_tx1_wrvalid_cnt = 0;
	 csr_write_enabled_cnt = 0;	 
      end
      else begin
	 // TX channels
	 if (rx_c0_cfgvalid) ase_rx0_cfgvalid_cnt <= ase_rx0_cfgvalid_cnt + 1;
	 if (rx_c0_rdvalid)  ase_rx0_rdvalid_cnt  <= ase_rx0_rdvalid_cnt + 1;
	 if (rx_c0_wrvalid)  ase_rx0_wrvalid_cnt  <= ase_rx0_wrvalid_cnt + 1;
	 if (rx_c1_wrvalid)  ase_rx1_wrvalid_cnt  <= ase_rx1_wrvalid_cnt + 1;
	 // TX channels
	 if (tx_c0_rdvalid)  ase_tx0_rdvalid_cnt  <= ase_tx0_rdvalid_cnt + 1;
	 if (tx_c1_wrvalid)  ase_tx1_wrvalid_cnt  <= ase_tx1_wrvalid_cnt + 1;
	 // CSR write enabled counting
	 if (csr_write_enabled) csr_write_enabled_cnt <= csr_write_enabled_cnt + 1;
      end
   end


   /*
    * This call is made on ERRORs requiring a shutdown
    * simkill is called from software, and is the final step before
    * graceful closedown
    */
   task simkill();
      begin
	 // CA-PCM deinitialize sequece
	 if (cfg.enable_capcm) begin
	    // capcm_deinit();
	 end
	 $display("SIM-SV: Simulation kill command received...");

	 // Valid Count
	 if (cfg.enable_asedbgdump) begin
	    // Print transactions
	    `BEGIN_YELLOW_FONTCOLOR;	    
	    $display("HW Transaction counts => ");
	    $display("\tConfigs    = %d", ase_rx0_cfgvalid_cnt );
	    $display("\tRdReq      = %d", ase_tx0_rdvalid_cnt );
	    $display("\tRdResp     = %d", ase_rx0_rdvalid_cnt );
	    $display("\tWrReq      = %d", ase_tx1_wrvalid_cnt );
	    $display("\tWrResp-CH0 = %d", ase_rx0_wrvalid_cnt );
	    $display("\tWrResp-CH1 = %d", ase_rx1_wrvalid_cnt );
	    $display("");
	    $display("\tcsr_write_enabled_cnt = %d", csr_write_enabled_cnt);
	    `END_YELLOW_FONTCOLOR;
	    // Print errors
	    `BEGIN_RED_FONTCOLOR;
	    if (ase_tx0_rdvalid_cnt != ase_rx0_rdvalid_cnt)
	      $display("\tREADs  : Response counts dont match request count !!");
	    if (ase_tx1_wrvalid_cnt != (ase_rx0_wrvalid_cnt + ase_rx1_wrvalid_cnt))
	      $display("\tWRITEs : Response counts dont match request count !!");
	    `END_RED_FONTCOLOR;	    
	 end
	 $finish;
      end
   endtask

   /*
    * Start daemon functions
    * - Buffer replicator: replicates access to DSM & Workspaces
    *   opened by application
    * - CSR_write listener: Receiver for CSR writes originating
    *   from SW application
    *
    */
   always @(posedge clk_32ui) begin : daemon_proc
      if (lp_initdone) begin
	 buffer_replicator();
	 csr_write_listener();
	 if (cfg.enable_umsg)
	   umsg_listener();	 
      end
   end


   /*
    * Read Line loop-around
    */
   logic 		       rdline_enabled;
   logic 		       rdline_completed;
   logic [31:0] 	       rdline_addr;
   logic [13:0] 	       rdline_meta;


   /*
    * TX1 to RX0/RX1 loop-around
    */
   // Bridge TX1-RX0
   logic tx1_to_rx0_enabled;
   logic tx1_to_rx0_completed;
   logic [`CCI_DATA_WIDTH-1:0] rx0_wrline_data;
   logic [13:0] 	       rx0_wrline_meta;
   logic [31:0] 	       rx0_wrline_addr;

   // Bridge TX1-RX1
   logic tx1_to_rx1_enabled;
   logic tx1_to_rx1_completed;
   logic [`CCI_DATA_WIDTH-1:0] rx1_wrline_data;
   logic [31:0] 	       rx1_wrline_addr;
   logic [13:0] 	       rx1_wrline_meta;
   int 			       ii;

   
   /* *******************************************************************
    * Forwarding path implementations
    * - ASE -> CAFU paths are pure FIFOs
    * - CAFU -> ASE paths are shuffling paths (with latency scoreboarding)
    *
    * *******************************************************************/
   // CAFU->ASE CH0
   logic [`CCI_TX_HDR_WIDTH-1:0] cf2as_latbuf_ch0_header;
   logic 			 cf2as_latbuf_ch0_read;
   logic 			 cf2as_latbuf_ch0_empty;

   // CAFU->ASE CH0
   logic [`CCI_TX_HDR_WIDTH-1:0] cf2as_latbuf_ch1_header;
   logic [`CCI_DATA_WIDTH-1:0] 	 cf2as_latbuf_ch1_data;
   logic 			 cf2as_latbuf_ch1_read;
   logic 			 cf2as_latbuf_ch1_empty;

   /*
    * RX0 channel management
    */
   // FSM states
   typedef enum { RX0_inactive,
		  RX0_csr_write_dex,
		  RX0_csr_action,
		  RX0_rdline_dex,
		  RX0_wrline_dex,
		  RX0_intr_dex,
		  RX0_umsg_dex,
		  RX0_write_fifo
		  } rx0_state_enum;
   rx0_state_enum rx0_state;

   // RX0 Write FIFO controls
   always @(posedge clk_32ui) begin
      rx_c0_cfgvalid <= 1'b0;
      rx_c0_wrvalid <= 1'b0;
      rx_c0_rdvalid <= 1'b0;
      rx_c0_umsgvalid <= 1'b0;
      rx_c0_intrvalid <= 1'b0;
      rx_c0_header <= `CCI_RX_HDR_WIDTH'b0;
      rx_c0_data <= `CCI_DATA_WIDTH'b0;
      rx0_active <= 1'b1;
      tx1_to_rx0_completed <= 1'b0;
      rdline_completed <= 1'b0;
      if (sys_reset_n == 1'b0) begin
	 sw_reset_n <= 1'b0;
	 rx0_state <= RX0_inactive;
      end
      else begin
	 sw_reset_n <= 1'b1;
	 case (rx0_state)
	   // Inactive
	   RX0_inactive:
	     begin
		rx0_active <=1'b0;
		rx0_pkt.cfgvalid <= 0;
		rx0_pkt.wrvalid <= 0;
		rx0_pkt.rdvalid <= 0;
		rx0_pkt.umsgvalid <= 0;
		rx0_pkt.intrvalid <= 0;
		rx0_pkt.meta <= 0;
		for(ii = 0; ii < 8; ii = ii + 1) begin
		   rx0_pkt.qword[ii] <= 0;
		end
		// Transaction filtering
		if (csr_write_enabled == 1) begin
		   rx0_state <= RX0_csr_write_dex;
		end
		else if ( (tx1_to_rx0_enabled == 1) && ((cf2as_latbuf_ch1_header[`TX_META_TYPERANGE]==`ASE_TX1_WRTHRU)||(cf2as_latbuf_ch1_header[`TX_META_TYPERANGE]==`ASE_TX1_WRLINE)) ) begin
		   rx0_state <= RX0_wrline_dex;
		end
		else if ( (rdline_enabled == 1'b1) && ((cf2as_latbuf_ch0_header[`TX_META_TYPERANGE]==`ASE_TX0_RDLINE)||(cf2as_latbuf_ch0_header[`TX_META_TYPERANGE]==`ASE_TX0_RDLINE_S)
						       ||(cf2as_latbuf_ch0_header[`TX_META_TYPERANGE]==`ASE_TX0_RDLINE_I)||(cf2as_latbuf_ch0_header[`TX_META_TYPERANGE]==`ASE_TX0_RDLINE_O)) ) begin
		   rx0_state <= RX0_rdline_dex;
		end
		else if (umsg_enabled == 1) begin
		   rx0_state <= RX0_umsg_dex;		   
		end
		else begin
		   rx0_state <= RX0_inactive;
		end
	     end // case: RX0_inactive

	   // CSR_write
	   RX0_csr_write_dex:
	     begin
		csr_write_dex (rx0_pkt);
		csr_write_completed();
	   	rx0_state <= RX0_csr_action;
	     end

	   // CSR action, implements some QLP behaviour
	   RX0_csr_action:
	     begin
		if (rx0_pkt.meta[`RX_CSR_BITRANGE] < CCI_AFU_LOW_OFFSET) begin
		   rx0_state <= RX0_inactive;
		   if (rx0_pkt.meta[`RX_CSR_BITRANGE] == CCI_RESET_CTRL_OFFSET ) begin
		      sw_reset_n <= ~rx0_pkt.qword[0][CCI_RESET_CTRL_BITLOC];
		   end
		   else begin
		      `BEGIN_YELLOW_FONTCOLOR;
		      $display("CSR_write: offset = %x data = %x ", rx0_pkt.meta[`RX_CSR_BITRANGE], rx0_pkt.qword[0][31:0] );
		      `END_YELLOW_FONTCOLOR;
		   end
		end
		else begin
		   rx0_state <= RX0_write_fifo;
		end
	   	csr_write_completed();
	     end

	   // RDLine response
	   RX0_rdline_dex:
	     begin
		rd_memline_dex (rx0_pkt, rdline_addr, rdline_meta );
		rdline_completed <= 1'b1;
		rx0_state <= RX0_write_fifo;
	     end

	   // WRline response
	   RX0_wrline_dex:
	     begin
		wr_memline_dex (rx0_pkt, rx0_wrline_addr, rx0_wrline_meta, rx0_wrline_data );
		tx1_to_rx0_completed <= 1'b1;
		rx0_state <= RX0_write_fifo;
	     end // case: RX0_wrline_dex

	   // Interrupt response *FIXME*
	   RX0_intr_dex:
	     begin
	     end

	   // Umsg valid *FIXME*
	   RX0_umsg_dex:
	     begin
		umsg_dex (rx0_pkt);
		umsg_completed();
		rx0_state <= RX0_write_fifo;		
	     end

	   // Write to RX0 FIFO
	   RX0_write_fifo:
	     begin
		tx1_to_rx0_completed <= 1'b0;
		rdline_completed <= 1'b0;
		rx0_state       <= RX0_inactive;
		rx_c0_cfgvalid  <= rx0_pkt.cfgvalid[0];
		rx_c0_wrvalid   <= rx0_pkt.wrvalid[0];
		rx_c0_rdvalid   <= rx0_pkt.rdvalid[0];
		rx_c0_umsgvalid <= rx0_pkt.umsgvalid[0];
		rx_c0_intrvalid <= rx0_pkt.intrvalid[0];
		rx_c0_header    <= rx0_pkt.meta[`CCI_RX_HDR_WIDTH-1:0];
		rx_c0_data      <= unpack_ccipkt_to_vector(rx0_pkt);
	     end // case: RX0_write_fifo

	   // Illegal
	   default:
	     begin
		rx0_state <= RX0_inactive;
	     end
	 endcase
      end
   end

   /*
    * RX1 Channel Management
    */
   // RX1 states
   typedef enum { RX1_inactive,
		  RX1_wrline_dex,
		  RX1_write_fifo
		  } rx1_state_enum;
   rx1_state_enum rx1_state;

   // RX1 control FSM
   always @(posedge clk_32ui) begin
      rx_c1_wrvalid <= 1'b0;
      rx_c1_intrvalid <= 1'b0;
      rx_c1_header  <= `CCI_RX_HDR_WIDTH'b0;
      rx1_active <= 1'b1;
      tx1_to_rx1_completed <= 1'b0;
      if (sys_reset_n == 1'b0) begin
	 rx1_state <= RX1_inactive;
      end
      else begin
	 case (rx1_state)
	   // Inactive
	   RX1_inactive:
	     begin
		rx1_active <= 1'b0;
		if ( (tx1_to_rx1_enabled == 1'b1) && ((cf2as_latbuf_ch1_header[`TX_META_TYPERANGE]==`ASE_TX1_WRTHRU)||(cf2as_latbuf_ch1_header[`TX_META_TYPERANGE]==`ASE_TX1_WRLINE))) begin
		   rx1_state <= RX1_wrline_dex;
		end
		else begin
		   rx1_state <= RX1_inactive;
		end
	     end // case: RX1_inactive

	   // Wrline Data-exchange
	   RX1_wrline_dex:
	     begin
		wr_memline_dex (rx1_pkt, rx1_wrline_addr, rx1_wrline_meta, rx1_wrline_data );
		tx1_to_rx1_completed <= 1'b1;
		rx1_state <= RX1_write_fifo;
	     end

	   // Write to TX1 FIFO
	   RX1_write_fifo:
	     begin
		rx1_state  <= RX1_inactive;
		rx_c1_wrvalid <= rx1_pkt.wrvalid[0];
		rx_c1_intrvalid <= rx1_pkt.intrvalid[0];
		rx_c1_header    <= rx1_pkt.meta[`CCI_RX_HDR_WIDTH-1:0];
	     end

	   // default
	   default:
	     begin
		rx1_state <= RX1_inactive;
	     end
	 endcase
      end
   end


   /*
    * CAFU->ASE CH0 (TX0)
    * Composed as {header, data}
    */
`ifdef ASE_RANDOMIZE_TRANSACTIONS
   // Latency scoreboard (for latency modeling and shuffling)
   latency_scoreboard
     #(
       .NUM_TRANSACTIONS (`LATBUF_NUM_TRANSACTIONS),
       .HDR_WIDTH        (`CCI_TX_HDR_WIDTH),
       .DATA_WIDTH       (`CCI_DATA_WIDTH),
       .COUNT_WIDTH      (`LATBUF_COUNT_WIDTH),
       .FIFO_FULL_THRESH (`LATBUF_FULL_THRESHOLD),
       .FIFO_DEPTH_BASE2 (`LATBUF_DEPTH_BASE2)
       )
   cf2as_latbuf_ch0
     (
      .clk		( clk_32ui ),
      .rst		( ~sys_reset_n ),
      .meta_in		( tx_c0_header ),
      .data_in		( {`CCI_DATA_WIDTH{1'b0}} ),
      .write_en		( tx_c0_rdvalid ),
      .meta_out		( cf2as_latbuf_ch0_header ),
      .data_out		(  ),
      .valid_out	(  ),
      .read_en		( cf2as_latbuf_ch0_read ),
      .empty		( cf2as_latbuf_ch0_empty ),
      .full             ( tx_c0_almostfull )
      );
`else // !`ifdef ASE_RANDOMIZE_TRANSACTIONS
   // FIFO (no randomization)
   ase_fifo
     #(
       .DATA_WIDTH     ( `CCI_TX_HDR_WIDTH ),
       .DEPTH_BASE2    ( `LATBUF_DEPTH_BASE2 ),
       .ALMFULL_THRESH ( `LATBUF_FULL_THRESHOLD )
       )
   cf2as_latbuf_ch0
     (
      .clk        ( clk_32ui ),
      .rst        ( ~sys_reset_n ),
      .wr_en      ( tx_c0_rdvalid ),
      .data_in    ( tx_c0_header ),
      .rd_en      ( cf2as_latbuf_ch0_read ),
      .data_out   ( cf2as_latbuf_ch0_header ),
      .data_out_v ( ),
      .alm_full   ( tx_c0_almostfull ),
      .full       ( ),
      .empty      ( cf2as_latbuf_ch0_empty ),
      .count      ( ),
      .overflow   ( ),
      .underflow  ( )
      );
`endif


   // TX0 states
   typedef enum {TX0_inactive,     // TX0 is empty, nothing to do
		 TX0_rx0_select,   // Respond with CH0
		 TX0_done          // TX0 done
		 } tx0_state_enum;
   tx0_state_enum tx0_state;

   // TX0 FSM
   always @(posedge clk_32ui) begin
      if (sys_reset_n == 1'b0) begin
	 cf2as_latbuf_ch0_read <= 1'b0;
	 tx0_state <= TX0_inactive;
      end
      else begin
	 case (tx0_state)
	   // Inactive
	   TX0_inactive:
	     begin
		cf2as_latbuf_ch0_read <= 1'b0;
		rdline_enabled <= 1'b0;
		rdline_addr <= 0;
		rdline_meta <= 0;
		if (cf2as_latbuf_ch0_empty != 1'b1) begin
		   tx0_state <= TX0_rx0_select;
		end
		else begin
		   tx0_state <= TX0_inactive;
		end
	     end // case: TX0_inactive

	   // ReadLine - wait for completion
	   TX0_rx0_select:
	     begin
		rdline_addr <= cf2as_latbuf_ch0_header[45:14];
		rdline_meta <= cf2as_latbuf_ch0_header[13:0];
		if (rdline_completed == 1'b1) begin
		   cf2as_latbuf_ch0_read <= 1'b1;
		   rdline_enabled <= 1'b0;
		   tx0_state <= TX0_done;
		end
		else begin
		   rdline_enabled <= 1'b1;
		   tx0_state <= TX0_rx0_select;
		end
	     end

	   // Done, stablize before moving to next
	   TX0_done:
	     begin
		cf2as_latbuf_ch0_read <= 1'b0;
		rdline_enabled <= 1'b0;
		tx0_state <= TX0_inactive;
	     end

	   // Undefined
	   default:
	     begin
		tx0_state <= TX0_inactive;
	     end
	 endcase
      end
   end


   /*
    * CAFU->ASE CH1 (TX1)
    */
`ifdef ASE_RANDOMIZE_TRANSACTIONS
   // Latency scoreboard (latency modeling and shuffling)
   latency_scoreboard
     #(
       .NUM_TRANSACTIONS (`LATBUF_NUM_TRANSACTIONS),
       .HDR_WIDTH        (`CCI_TX_HDR_WIDTH),
       .DATA_WIDTH       (`CCI_DATA_WIDTH),
       .COUNT_WIDTH      (`LATBUF_COUNT_WIDTH),
       .FIFO_FULL_THRESH (`LATBUF_FULL_THRESHOLD),
       .FIFO_DEPTH_BASE2 (`LATBUF_DEPTH_BASE2)
       )
   cf2as_latbuf_ch1
     (
      .clk		( clk_32ui ),
      .rst		( ~sys_reset_n ),
      .meta_in		( tx_c1_header ),
      .data_in		( tx_c1_data ),
      .write_en		( tx_c1_wrvalid ),
      .meta_out		( cf2as_latbuf_ch1_header ),
      .data_out		( cf2as_latbuf_ch1_data ),
      .valid_out	(  ),
      .read_en		( cf2as_latbuf_ch1_read ),
      .empty		( cf2as_latbuf_ch1_empty ),
      .full             ( tx_c1_almostfull )
      );
`else // !`ifdef ASE_RANDOMIZE_TRANSACTIONS
   // FIFO (no shuffling, simple forwarding)

   // Drop WrFence.  No response expected and writes are already ordered.
   logic cf2as_latbuf_ch1_wr_en;
   assign cf2as_latbuf_ch1_wr_en = tx_c1_wrvalid && (tx_c1_header[`TX_META_TYPERANGE] != `ASE_TX1_WRFENCE);

   ase_fifo
     #(
       .DATA_WIDTH     ( `CCI_TX_HDR_WIDTH + `CCI_DATA_WIDTH ),
       .DEPTH_BASE2    ( `LATBUF_DEPTH_BASE2 ),
       .ALMFULL_THRESH ( `LATBUF_FULL_THRESHOLD )
       )
   cf2as_latbuf_ch1
     (
      .clk        ( clk_32ui ),
      .rst        ( ~sys_reset_n ),
      .wr_en      ( cf2as_latbuf_ch1_wr_en ),
      .data_in    ( {tx_c1_header,tx_c1_data} ),
      .rd_en      ( cf2as_latbuf_ch1_read ),
      .data_out   ( {cf2as_latbuf_ch1_header,cf2as_latbuf_ch1_data} ),
      .data_out_v ( ),
      .alm_full   ( tx_c1_almostfull ),
      .full       ( ),
      .empty      ( cf2as_latbuf_ch1_empty ),
      .count      ( ),
      .overflow   ( ),
      .underflow  ( )
      );
`endif


   // TX1 states
   typedef enum { TX1_inactive,    // TX1 is empty, nothing to do
		  TX1_rx0_select,  // Respond with CH0
		  TX1_rx1_select,  // Respond with CH1
		  TX1_done         // TX1 done
		  } tx1_state_enum;
   tx1_state_enum tx1_state;

   // TX1 FSM
   always @(posedge clk_32ui) begin
      cf2as_latbuf_ch1_read <= 1'b0;
      if (sys_reset_n == 1'b0) begin
	 tx1_to_rx0_enabled <= 1'b0;
	 tx1_to_rx1_enabled <= 1'b0;
	 rx0_wrline_meta    <= 14'b0;
	 rx0_wrline_addr    <= 32'b0;
	 rx0_wrline_data    <= `CCI_DATA_WIDTH'b0;
	 rx1_wrline_meta    <= 14'b0;
	 rx1_wrline_addr    <= 32'b0;
	 rx1_wrline_data    <= `CCI_DATA_WIDTH'b0;
	 tx1_state <= TX1_inactive;
      end
      else begin
	 case (tx1_state)
	   // Inactive
	   TX1_inactive:
	     begin
		tx1_to_rx0_enabled <= 1'b0;
		tx1_to_rx1_enabled <= 1'b0;
		rx0_wrline_meta    <= 14'b0;
		rx0_wrline_addr    <= 32'b0;
		rx0_wrline_data    <= `CCI_DATA_WIDTH'b0;
		rx1_wrline_meta    <= 0;
		rx1_wrline_addr    <= 32'b0;
		rx1_wrline_data    <= `CCI_DATA_WIDTH'b0;
		if ((cf2as_latbuf_ch1_empty != 1'b1) && (rx_free == 1'b1) && (find_free_rx_channel() == 0)) begin
		   tx1_state <= TX1_rx0_select;
		end
		else if ((cf2as_latbuf_ch1_empty != 1'b1) && (rx_free == 1'b1) && (find_free_rx_channel() == 1)) begin
		   tx1_state <= TX1_rx1_select;
		end
		else begin
		   tx1_state <= TX1_inactive;
		end
	     end // case: TX1_inactive

	   // Write request occured
	   TX1_rx0_select:
	     begin
		rx0_wrline_meta    <= cf2as_latbuf_ch1_header[13:0];
		rx0_wrline_addr    <= cf2as_latbuf_ch1_header[45:14];
		rx0_wrline_data    <= cf2as_latbuf_ch1_data;
		if (tx1_to_rx0_completed == 1'b1) begin
		   cf2as_latbuf_ch1_read <= 1'b1;
		   tx1_to_rx0_enabled <= 1'b0;
		   tx1_state <= TX1_done;
		end
		else begin
		   tx1_to_rx0_enabled <= 1'b1;
		   tx1_state <= TX1_rx0_select;
		end
	     end // case: TX1_rx0_select

	   // Interrupt request occured
	   TX1_rx1_select:
	     begin
		rx1_wrline_meta    <= cf2as_latbuf_ch1_header[13:0];
		rx1_wrline_addr    <= cf2as_latbuf_ch1_header[45:14];
		rx1_wrline_data    <= cf2as_latbuf_ch1_data;
		if (tx1_to_rx1_completed == 1'b1) begin
		   cf2as_latbuf_ch1_read <= 1'b1;
		   tx1_to_rx1_enabled <= 1'b0;
		   tx1_state <= TX1_done;
		end
		else begin
		   tx1_to_rx1_enabled <= 1'b1;
		   tx1_state <= TX1_rx1_select;
		end
	     end // case: TX1_rx1_select

	   // Done state
	   TX1_done:
	     begin
		cf2as_latbuf_ch1_read <= 1'b0;
		tx1_state <= TX1_inactive;
	     end

	   // Undefined
	   default:
	     begin
		tx1_state <= TX1_inactive;
	     end
	 endcase
      end
   end


   /* *******************************************************************
    * Inactivity management block
    *
    * DESCRIPTION: Running ASE simulations for too long can cause
    *              large dump-files to be formed. To prevent this, the
    *              inactivity counter will close down the simulation
    *              when CCI transactions are not seen for a long
    *              duration of time.
    *
    * This feature can be disabled, if desired.
    *
    * *******************************************************************/
   logic 	    first_transaction_seen = 0;
   logic [31:0]     inactivity_counter;
   logic 	    any_valid;
   logic 	    inactivity_found;


   // Inactivity management - Sense first transaction
   assign any_valid =    rx_c0_umsgvalid
		      || tx_c1_intrvalid_sel
		      || rx_c0_intrvalid
		      || rx_c1_intrvalid
		      || rx_c0_wrvalid
                      || rx_c0_rdvalid
                      || rx_c0_cfgvalid
                      || rx_c1_wrvalid
                      || tx_c0_rdvalid
                      || tx_c1_wrvalid ;


   // Check for first transaction
   always @(posedge clk_32ui, any_valid)
     begin
	if(any_valid) begin
	   first_transaction_seen <= 1'b1;
	end
     end

   // Inactivity management - killswitch
   always @(posedge clk_32ui) begin
      if((inactivity_found==1'b1) && (cfg.enable_timeout != 0)) begin
	 $display("SIM-SV: Inactivity timeout reached !!\n");
	 start_simkill_countdown();
      end
   end

   // Inactivity management - counter
   counter
     #(
       .COUNT_WIDTH (32)
       )
   inact_ctr
     (
      .clk          (clk_32ui),
      .rst          ( first_transaction_seen && any_valid ),
      .cnt_en       (1'b1),
      .load_cnt     (32'b0),
      .max_cnt      (cfg.enable_timeout),
      .count_out    (inactivity_counter),
      .terminal_cnt (inactivity_found)
      );


   /* ****************************************************************
    * Initialising the CAFU here.
    * If SPL2 is enabled, SPL top is mapped
    * If CCI is enabled, cci_std_afu.sv is mapped
    *
    * ****************************************************************
    *
    *              ASE   |             |   CAFU or (SPL + AFU)
    *                  TX|------------>|RX
    *                    |             |
    *                  RX|<------------|TX
    *                    |             |
    *
    * ***************************************************************/
   cci_std_afu cci_std_afu (
			    /* Link/Protocol (LP) clocks and reset */
			    .vl_clk_LPdomain_32ui             ( clk_32ui ),
			    .vl_clk_LPdomain_16ui             ( clk_16ui ),
			    .ffs_vl_LP32ui_lp2sy_InitDnForSys ( lp_initdone ),
			    .ffs_vl_LP32ui_lp2sy_SystemReset_n( sys_reset_n ),
			    .ffs_vl_LP32ui_lp2sy_SoftReset_n  ( sw_reset_n ),
			    /* Channel 0 can receive READ, WRITE, WRITE CSR responses.*/
			    .ffs_vl18_LP32ui_lp2sy_C0RxHdr    ( rx_c0_header ),
			    .ffs_vl512_LP32ui_lp2sy_C0RxData  ( rx_c0_data ),
			    .ffs_vl_LP32ui_lp2sy_C0RxWrValid  ( rx_c0_wrvalid ),
			    .ffs_vl_LP32ui_lp2sy_C0RxRdValid  ( rx_c0_rdvalid ),
			    .ffs_vl_LP32ui_lp2sy_C0RxCgValid  ( rx_c0_cfgvalid ),
			    .ffs_vl_LP32ui_lp2sy_C0RxUgValid  ( rx_c0_umsgvalid ),
			    .ffs_vl_LP32ui_lp2sy_C0RxIrValid  ( rx_c0_intrvalid ),
			    /* Channel 1 reserved for WRITE RESPONSE ONLY */
			    .ffs_vl18_LP32ui_lp2sy_C1RxHdr    ( rx_c1_header ),
			    .ffs_vl_LP32ui_lp2sy_C1RxWrValid  ( rx_c1_wrvalid ),
			    .ffs_vl_LP32ui_lp2sy_C1RxIrValid  ( rx_c1_intrvalid ),
			    /*Channel 0 reserved for READ REQUESTS ONLY */
			    .ffs_vl61_LP32ui_sy2lp_C0TxHdr    ( tx_c0_header ),
			    .ffs_vl_LP32ui_sy2lp_C0TxRdValid  ( tx_c0_rdvalid ),
			    /*Channel 1 reserved for WRITE REQUESTS ONLY */
			    .ffs_vl61_LP32ui_sy2lp_C1TxHdr    ( tx_c1_header ),
			    .ffs_vl512_LP32ui_sy2lp_C1TxData  ( tx_c1_data ),
			    .ffs_vl_LP32ui_sy2lp_C1TxWrValid  ( tx_c1_wrvalid ),
			    .ffs_vl_LP32ui_sy2lp_C1TxIrValid  ( tx_c1_intrvalid ),
			    /* Tx push flow control */
			    .ffs_vl_LP32ui_lp2sy_C0TxAlmFull  ( tx_c0_almostfull ),
			    .ffs_vl_LP32ui_lp2sy_C1TxAlmFull  ( tx_c1_almostfull )
			    );



   /*
    * Initialization procedure
    *
    * DESCRIPTION: This procedural block is called when ./simv is
    *              kicked off, helps put the simulation in a known
    *              state.
    *
    * STEPS:
    * - Print startup info
    * - Send initial system reset, cleaning up state machines
    * - Initialize ASE (ase_init executes in SW)
    *   - Set up message queues for IPC (done in SW)
    *   - Set up memory management structure (called in SW)
    * - If ENABLED, start the CA-private memory region (emulated with
    *   software
    * - Then set up the QLP InitDone signal to go indicate readiness
    * - SIMULATION is ready to begin
    *
    */
   initial begin : ase_entry_point
      $display("SIM-SV: Simulator started...");
      // Initialize data-structures
      ase_init();

      // Initial signal values *FIXME*
      $display("SIM-SV: Sending initial reset...");
      sys_reset_n = 0;
      // for (sys_rst_iter=0; sys_rst_iter<`INITIAL_SYSTEM_RESET_DURATION; sys_rst_iter = sys_rst_iter + 1) begin
      // 	 @(posedge clk);
      // end
      #100ns;
      
      sys_reset_n = 1;
      // for (sys_rst_iter=0; sys_rst_iter<`INITIAL_SYSTEM_RESET_DURATION; sys_rst_iter = sys_rst_iter + 1) begin
      // 	 @(posedge clk);
      // end
      #100ns;
      
      // Setting up CA-private memory
      // if (ENABLE_CACHING_AGENT_PRIVATE_MEMORY) begin
      if (cfg.enable_capcm) begin
	 $display("SIM-SV: Enabling structures for CA Private Memory... ");
	 capcm_init();	 
      end

      // Link layer ready signal
      wait (lp_initdone == 1'b1);
      $display("SIM-SV: CCI InitDone is HIGH...");

      // Indicate to APP that ASE is ready
      ase_ready();

   end


   /*
    * Latency pipe : For LP_InitDone delay
    * This block simulates the latency between a generic reset and QLP
    * InitDone
    */
   latency_pipe
     #(
       .NUM_DELAY (`LP_INITDONE_READINESS_LATENCY),
       .PIPE_WIDTH (1)
       )
   lp_initdone_lat
     (
      .clk (clk_32ui),
      .rst (~sys_reset_n),
      .pipe_in (sys_reset_n),
      .pipe_out (lp_initdone)
      );


   /*
    * CCI rule-checker function
    * This block of code exists for checking incoming signals for 'X' & 'Z'
    * Warning messages will be flashed, and simulation exited, when enabled
    */
   // Used for rule-checking meta-only transactions
   logic [`CCI_DATA_WIDTH-1:0] 		  zero_data = `CCI_DATA_WIDTH'b0;
   logic 				  tx0_rc_error;
   logic 				  tx1_rc_error;
   logic 				  rx0_rc_error;
   logic 				  rx1_rc_error;
   int 					  tx0_rc_time;
   int 					  tx1_rc_time;
   int 					  rx0_rc_time;
   int 					  rx1_rc_time;


   // Initial message
   initial begin
      if (cfg.enable_ccirules) begin
	 $display("SIM-SV: CCI Signal rule-checker is watching for 'X' and 'Z'");
      end
   end

   // CCI Rules Checker: Checking CCI for 'X' and 'Z' endorsed by valid signal
   cci_rule_checker
     #(
       .TX_HDR_WIDTH (`CCI_TX_HDR_WIDTH),
       .RX_HDR_WIDTH (`CCI_RX_HDR_WIDTH),
       .DATA_WIDTH   (`CCI_DATA_WIDTH)
       )
   cci_rule_checker
     (
      // Enable
      .enable          (cfg.enable_ccirules[0]),
      // CCI signals
      .clk             (clk_32ui),
      .resetb          (sys_reset_n),
      .lp_initdone     (lp_initdone),
      .tx_c0_header    (tx_c0_header),
      .tx_c0_rdvalid   (tx_c0_rdvalid),
      .tx_c1_header    (tx_c1_header),
      .tx_c1_data      (tx_c1_data),
      .tx_c1_wrvalid   (tx_c1_wrvalid),
      .tx_c1_intrvalid (tx_c1_intrvalid_sel ),
      .rx_c0_header    (rx_c0_header),    
      .rx_c0_data      (rx_c0_data),      
      .rx_c0_rdvalid   (rx_c0_rdvalid),   
      .rx_c0_wrvalid   (rx_c0_wrvalid),   
      .rx_c0_cfgvalid  (rx_c0_cfgvalid),  
      .rx_c1_header    (rx_c1_header),    
      .rx_c1_wrvalid   (rx_c1_wrvalid),   
      // Error signals
      .tx_ch0_error    (tx0_rc_error),
      .tx_ch1_error    (tx1_rc_error),
      .rx_ch0_error    (rx0_rc_error),
      .rx_ch1_error    (rx1_rc_error),
      .tx_ch0_time     (tx0_rc_time),
      .tx_ch1_time     (tx1_rc_time),
      .rx_ch0_time     (rx0_rc_time),
      .rx_ch1_time     (rx1_rc_time)
      );

   // Interrupt select (enables
   assign tx_c1_intrvalid_sel = cfg.enable_intr ? tx_c1_intrvalid : 1'b0 ;


   // Call simkill on bad outcome of checker process
   task checker_simkill(int sim_time) ;
      begin
   	 `BEGIN_RED_FONTCOLOR;
   	 $display("SIM-SV: ASE has detected 'Z' or 'X' were qualified by a valid signal.");
   	 $display("SIM-SV: Check simulation around time, t = %d", sim_time);
   	 $display("SIM-SV: Simulation will end now");
   	 $display("SIM-SV: If 'X' or 'Z' are intentional, set ENABLE_CCI_RULES to '0' in ase.cfg file");
   	 `END_RED_FONTCOLOR;
   	 start_simkill_countdown();
      end
   endtask

   // Watch checker signal
   always @(posedge clk_32ui) begin
      if (tx0_rc_error) begin
	 checker_simkill(tx0_rc_time);
      end
      else if (tx1_rc_error) begin
	 checker_simkill(tx1_rc_time);
      end
      else if (rx0_rc_error) begin
	 checker_simkill(rx0_rc_time);
      end
      else if (rx1_rc_error) begin
	 checker_simkill(rx1_rc_time);
      end
   end


   /*
    * ASE Hardware Interface (CCI) logger
    * - Logs CCI transaction into a transactions.tsv file
    * - Watch for "*valid", and write transaction to log name
    */
   // Log file descriptor
   int log_fd;

   // Registers for comparing previous states
   always @(posedge clk_32ui) begin
      lp_initdone_q <= lp_initdone;
      resetb_q <= resetb;
      sw_reset_n_q <= sw_reset_n;
   end


   /*
    * Watcher process
    */
   initial begin : logger_proc
      // Display
      $display("SIM-SV: CCI Logger started");

      // Open transactions.tsv file
      log_fd = $fopen("transactions.tsv", "w");

      // Headers
      $fwrite(log_fd, "\tTime\tTransactionType\tChannel\tMetaInfo\tCacheAddr\tData\n");

      // Watch CCI port
      forever begin
	 // If LP_initdone changed, log the event
	 if (lp_initdone_q != lp_initdone) begin
	    $fwrite(log_fd, "%d\tLP_initdone toggled from %b to %b\n", $time, lp_initdone_q, lp_initdone);
	 end
	 // Indicate Software controlled reset
	 if (sw_reset_n_q != sw_reset_n) begin
	    $fwrite(log_fd, "%d\tSoftware reset toggled from %b to %b\n", $time, sw_reset_n_q, sw_reset_n);
	 end
	 // If reset toggled, log the event
	 if (resetb_q != resetb) begin
	    $fwrite(log_fd, "%d\tResetb toggled from %b to %b\n", $time, resetb_q, resetb);
	 end
	 // Watch CCI for valid transactions
	 if (lp_initdone) begin
	    ////////////////////////////// RX0 cfgvalid /////////////////////////////////
	    if (rx_c0_cfgvalid) begin
	       $fwrite(log_fd, "%d\tCSRWrite\t0\tNA\t%x\t%x\n", $time, rx_c0_header[`RX_CSR_BITRANGE], rx_c0_data[31:0]);
	       if (cfg.enable_cl_view) $display("%d\tCSRWrite\t0\tNA\t%x\t%x", $time, rx_c0_header[`RX_CSR_BITRANGE], rx_c0_data[`CCI_CSR_WIDTH]);
	    end
	    /////////////////////////////// RX0 wrvalid /////////////////////////////////
	    if (rx_c0_wrvalid) begin
	       $fwrite(log_fd, "%d\tWrResp\t\t0\t%x\tNA\tNA\n", $time, rx_c0_header[`RX_MDATA_BITRANGE] );
	       if (cfg.enable_cl_view) $display("%d\tWrResp\t\t0\t%x\tNA\tNA", $time, rx_c0_header[`RX_MDATA_BITRANGE] );
	    end
	    /////////////////////////////// RX0 rdvalid /////////////////////////////////
	    if (rx_c0_rdvalid) begin
	       $fwrite(log_fd, "%d\tRdResp\t\t0\t%x\tNA\t%x\n", $time, rx_c0_header[`RX_MDATA_BITRANGE], rx_c0_data );
	       if (cfg.enable_cl_view) $display("%d\tRdResp\t\t0\t%x\tNA\t%x", $time, rx_c0_header[`RX_MDATA_BITRANGE], rx_c0_data );
	    end
	    ////////////////////////////// RX0 umsgvalid ////////////////////////////////
	    if (rx_c0_umsgvalid) begin
	       if (rx_c0_header[`CCI_UMSG_BITINDEX]) begin              // Umsg Hint
		  $fwrite(log_fd, "%d\tUmsgHint\t0\n", $time );
		  if (cfg.enable_cl_view) $display("%d\tUmsgHint\t\t0\n", $time );
	       end
	       else begin                                               // Umsg with data
		  $fwrite(log_fd, "%d\tUmsg    \t0\t%x\n", $time, rx_c0_data );
		  if (cfg.enable_cl_view) $display("%d\tUmsgHint\t\t0\t%x\n", $time, rx_c0_data ); 
	       end
	    end
	    /////////////////////////////// RX1 wrvalid /////////////////////////////////
	    if (rx_c1_wrvalid) begin
	       $fwrite(log_fd, "%d\tWrResp\t\t1\t%x\tNA\tNA\n", $time, rx_c1_header[`RX_MDATA_BITRANGE] );
	       if (cfg.enable_cl_view) $display("%d\tWrResp\t\t1\t%x\tNA\tNA", $time, rx_c1_header[`RX_MDATA_BITRANGE] );
	    end
	    /////////////////////////////// TX0 rdvalid /////////////////////////////////
	    if (tx_c0_rdvalid) begin
	       if ((tx_c0_header[`TX_META_TYPERANGE] == `ASE_TX0_RDLINE_S) || (tx_c0_header[`TX_META_TYPERANGE] == `ASE_TX0_RDLINE)) begin
		  $fwrite(log_fd, "%d\tRdLineReq_S\t0\t%x\t%x\tNA\n", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
		  if (cfg.enable_cl_view) $display("%d\tRdLineReq_S\t0\t%x\t%x\tNA", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
	       end
	       else if (tx_c0_header[`TX_META_TYPERANGE] == `ASE_TX0_RDLINE_I) begin
		  $fwrite(log_fd, "%d\tRdLineReq_I\t0\t%x\t%x\tNA\n", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
		  if (cfg.enable_cl_view) $display("%d\tRdLineReq_I\t0\t%x\t%x\tNA", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
	       end
	       else if (tx_c0_header[`TX_META_TYPERANGE] == `ASE_TX0_RDLINE_O) begin
		  $fwrite(log_fd, "%d\tRdLineReq_O\t0\t%x\t%x\tNA\n", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
		  if (cfg.enable_cl_view) $display("%d\tRdLineReq_O\t0\t%x\t%x\tNA", $time, tx_c0_header[`TX_MDATA_BITRANGE], tx_c0_header[45:14]);
	       end
	       else begin
		  $fwrite(log_fd, "ReadValid on TX-CH0 validated an UNKNOWN Request type at t = %d \n", $time);
	       end
	    end
	    /////////////////////////////// TX1 wrvalid /////////////////////////////////
	    if (tx_c1_wrvalid) begin
	       if (tx_c1_header[`TX_META_TYPERANGE] == `ASE_TX1_WRTHRU) begin
		  $fwrite(log_fd, "%d\tWrThruReq\t1\t%x\t%x\t%x\n", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14], tx_c1_data);
		  if (cfg.enable_cl_view) $display("%d\tWrThruReq\t1\t%x\t%x\t%x", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14], tx_c1_data);
	       end
	       else if (tx_c1_header[`TX_META_TYPERANGE] == `ASE_TX1_WRLINE) begin
		  $fwrite(log_fd, "%d\tWrLineReq\t1\t%x\t%x\t%x\n", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14], tx_c1_data);
		  if (cfg.enable_cl_view) $display("%d\tWrLineReq\t1\t%x\t%x\t%x", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14], tx_c1_data);
	       end
	       else if (tx_c1_header[`TX_META_TYPERANGE] == `ASE_TX1_WRFENCE) begin
		  $fwrite(log_fd, "%d\tWrFence\t1\t%x\t%x\n", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14]);
		  if (cfg.enable_cl_view) $display("%d\tWrFence\t1\t%x\t%x\n", $time, tx_c1_header[`TX_MDATA_BITRANGE], tx_c1_header[45:14]);
	       end
	       else begin
		  $fwrite(log_fd, "WriteValid on TX-CH1 validated an UNKNOWN Request type at t = %d \n", $time);
		  if (cfg.enable_cl_view) $display("WriteValid on TX-CH1 validated an UNKNOWN Request type at t = %d \n", $time);
	       end
	    end
	 end
	 // Wait till next clock
	 @(posedge clk_32ui);

      end
   end


endmodule // cci_emulator
