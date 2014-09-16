// ------------------------------------------------------------------
// CCI to memory translator - SystemVerilog Module
// Author: Rahul R Sharma
//         Intel Corporation
//
// UPGRADES:
// - RRS: Wed Aug 10 22:17:28 PDT 2011
//   Completed FIFO'ing all channels in all directions
//
// -------------------------------------------------------------------
// This module is a DPI SV side module that interfaces with CAFU
// RTL. Transactions to and from software and imported/exported to DPI
// C-side code. The DPI C-side file is cci_mem_translator.c
//
// WARNING: This file is **not designed to be edited**. Editing this
// file might violate code sanity. Only the "dpi_common.vh" header
// file must be edited if some parameters need to be changed.
//
// -------------------------------------------------------------------

// CCI modules definitions
// `include "dpi_global.vh"
`include "ase_global.vh"
`include "platform.vh"

// CCI to Memory translator module
module cci_mem_translator;

   // ---------------------------------------------------------------
   // DPI import/export functions
   // ---------------------------------------------------------------
   import "DPI-C" context task ase_init();
   import "DPI-C" context task cci_rdline_req(int cl_rd_addr, int mdata);
   import "DPI-C" context task cci_wrline_req(int cl_wr_addr, int mdata, bit [511:0] wr_data);
   import "DPI-C" context task cci_intr_req(int intr_id);
   import "DPI-C" context task buffer_replicator();
   import "DPI-C" context task csr_write_listener();
   import "DPI-C" context task start_simkill_countdown();
   import "DPI-C" context task capcm_init(int num_cl);
   import "DPI-C" context task capcm_rdline_req(int cl_addr, int mdata);
   import "DPI-C" context task capcm_wrline_req(int cl_addr, int mdata, bit [511:0] cl_data);
   import "DPI-C" context task capcm_deinit();
      
   export "DPI-C" task simkill;
   export "DPI-C" task cci_ase2cafu_csr_ch0;
   export "DPI-C" task cci_ase2cafu_rdResp_ch0;
   export "DPI-C" task cci_ase2cafu_wrResp_ch0;
   export "DPI-C" task cci_ase2cafu_ch1;
//   export "DPI-C" task cci_ase2cafu_umsg_ch0;
   // export "DPI-C" task capcm_ase2cafu_wrResp_ch0;
   // export "DPI-C" task capcm_wrline_resp;

   // --------------------------------------------------------------------------
   // CCI signals declarations
   // --------------------------------------------------------------------------
   // Convention - ground rules
   // REF diagram: CCI_Specificiation_Rev0.9.pdf - page 7
   //                          -------------------
   //   tx0_header     ---61-->|                 |---18---> rx0_header
   //   tx0_valid      ------->|                 |---512--> rx0_data
   //   tx0_almostfull <-------|                 |--------> rx0_rdvalid
   //   tx1_header     ---61-->|      ASE        |--------> rx0_wrvalid
   //   tx1_data       --512-->|     BLOCK       |--------> rx0_cfgvalid
   //   tx1_valid      ------->|                 |--------> rx0_umsgvalid (TBD)
   //   tx1_almostfull <-------|                 |--------> rx0_intrvalid (TBD)
   //   tx1_intrvalid  ------->|                 |---18---> rx1_header
   //                          |                 |--------> rx1_intrvalid (TBD)
   //                          |                 |--------> rx1_wrvalid
   //                          |                 |--------> lp_initdone
   //                          |                 |--------> reset
   //                          |                 |--------> clk
   //                          -------------------
   //
   // CONVENTION: {ase2cafu|cafu2ase}_ch{0|1}_<name>
   // WARNING: Do not use TX/RX here as these can be confused with CAFU TX/RX
   // ase2cafu - Signals originating in DPI
   // cafu2ase - Signals originating in CAFU
   // 0/1     - Channel number
   //
   // MODIFIED:
   // - Thu Aug  4 10:54:49 PDT 2011: CCI 1.8 diagram
   // --------------------------------------------------------------------------
   //        DPI Block signal name         // Name in diagram
   // --------------------------------------------------------------------------
   logic                          clk   ;                  // out
   logic 			  resetb ;                 // out
   logic 			  lp_initdone ;            // out
   logic [`CCI_TX0_HDR_WIDTH-1:0] tx_c0_header;            // in
   logic 			  tx_c0_rdvalid;           // in
   logic 			  tx_c0_almostfull;        // out
   logic [`CCI_TX1_HDR_WIDTH-1:0] tx_c1_header;            // in
   logic [`CCI_DATA_WIDTH-1:0] 	  tx_c1_data;              // in
   logic 			  tx_c1_wrvalid;           // in
   logic 			  tx_c1_almostfull;        // out
   logic [`CCI_RX0_HDR_WIDTH-1:0] rx_c0_header;            // out
   logic [`CCI_DATA_WIDTH-1:0] 	  rx_c0_data;              // out
   logic 			  rx_c0_rdvalid;           // out
   logic 			  rx_c0_wrvalid;           // out
   logic 			  rx_c0_cfgvalid;          // out
   logic [`CCI_RX1_HDR_WIDTH-1:0] rx_c1_header;            // out
   logic 			  rx_c1_wrvalid;           // out
`ifdef ENABLE_CCI_UMSG_IF
   logic 			  rx_c0_umsgvalid;
`endif
`ifdef ENABLE_CCI_INTR_IF
   logic 			  tx_c1_intrvalid;
   logic 			  rx_c0_intrvalid;
   logic 			  rx_c1_intrvalid;
`endif

   // Software and system reset
   logic 			  sys_reset = 0;
   logic 			  sw_reset = 0;

   // =========================================================
   // FIFO: store request from channel 0 in FIFO A
   // ---------------------------------------------------------
   logic [`CCI_TX0_HDR_WIDTH-1:0] req_c0_fifo_a_din_header;
   logic 			  req_c0_fifo_a_write = 0;
   logic 			  req_c0_fifo_a_read = 0;
   logic 			  req_c0_fifo_a_empty;
   logic [`CCI_TX0_HDR_WIDTH-1:0] req_c0_fifo_a_dout_header;
   logic 			  req_c0_fifo_a_dout_legal;
   logic 			  req_c0_fifo_a_almostfull;

   // =========================================================
   // FIFO: store request from channel 0 in FIFO B
   // ---------------------------------------------------------
   logic [`CCI_TX0_HDR_WIDTH-1:0] req_c0_fifo_b_din_header;
   logic 			  req_c0_fifo_b_write = 0;
   logic 			  req_c0_fifo_b_read = 0;
   logic 			  req_c0_fifo_b_empty;
   logic [`CCI_TX0_HDR_WIDTH-1:0] req_c0_fifo_b_dout_header;
   logic 			  req_c0_fifo_b_dout_legal;
   logic 			  req_c0_fifo_b_almostfull;

   logic [`CCI_TX0_HDR_WIDTH-1:0] req_c0_fifo_dout_header;
   logic 			  req_c0_fifo_dout_legal;

   // =========================================================
   // FIFO: store request from channel 1 in FIFO A
   // ---------------------------------------------------------
   logic [`CCI_TX1_HDR_WIDTH-1:0] req_c1_fifo_a_din_header;
   logic [`CCI_DATA_WIDTH-1:0] 	  req_c1_fifo_a_din_data;
   logic 			  req_c1_fifo_a_write = 0;
   logic 			  req_c1_fifo_a_read = 0;
   logic 			  req_c1_fifo_a_empty;
   logic [`CCI_TX1_HDR_WIDTH-1:0] req_c1_fifo_a_dout_header;
   logic [`CCI_DATA_WIDTH-1:0] 	  req_c1_fifo_a_dout_data;
   logic 			  req_c1_fifo_a_dout_legal;
   logic 			  req_c1_fifo_a_almostfull;

   // =========================================================
   // FIFO: store request from channel 1 in FIFO B
   // ---------------------------------------------------------
   logic [`CCI_TX1_HDR_WIDTH-1:0] req_c1_fifo_b_din_header;
   logic [`CCI_DATA_WIDTH-1:0] 	  req_c1_fifo_b_din_data;
   logic 			  req_c1_fifo_b_write = 0;
   logic 			  req_c1_fifo_b_read = 0;
   logic 			  req_c1_fifo_b_empty;
   logic [`CCI_TX1_HDR_WIDTH-1:0] req_c1_fifo_b_dout_header;
   logic [`CCI_DATA_WIDTH-1:0] 	  req_c1_fifo_b_dout_data;
   logic 			  req_c1_fifo_b_dout_legal;
   logic 			  req_c1_fifo_b_almostfull;

   logic [`CCI_TX1_HDR_WIDTH-1:0] req_c1_fifo_dout_header;
   logic [`CCI_DATA_WIDTH-1:0] 	  req_c1_fifo_dout_data;
   logic 			  req_c1_fifo_dout_legal;


   // =========================================================
   // FIFO: store csr responses on channel 0
   // ---------------------------------------------------------
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_csr_fifo_din;   // data + header + valid x 5
   logic 						resp_c0_csr_fifo_read;
   logic 						resp_c0_csr_fifo_write;
   logic 						resp_c0_csr_fifo_empty;
   logic 						resp_c0_csr_fifo_almostfull;
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_csr_fifo_dout;
   logic 						resp_c0_csr_fifo_dout_legal;

   // =========================================================
   // FIFO: store read responses on channel 0
   // ---------------------------------------------------------
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_rd_fifo_din;   // data + header + valid x 5
   logic 						resp_c0_rd_fifo_read;
   logic 						resp_c0_rd_fifo_write;
   logic 						resp_c0_rd_fifo_empty;
   logic 						resp_c0_rd_fifo_almostfull;
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_rd_fifo_dout;
   logic 						resp_c0_rd_fifo_dout_legal;

   // =========================================================
   // FIFO: store write responses on channel 0
   // ---------------------------------------------------------
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_wr_fifo_din;   // data + header + valid x 5
   logic 						resp_c0_wr_fifo_read;
   logic 						resp_c0_wr_fifo_write;
   logic 						resp_c0_wr_fifo_empty;
   logic 						resp_c0_wr_fifo_almostfull;
   logic [((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3)-1):0] resp_c0_wr_fifo_dout;
   logic 						resp_c0_wr_fifo_dout_legal;

   // =========================================================
   // FIFO: store write responses on channel 1
   // ---------------------------------------------------------
   logic [(`CCI_RX1_HDR_WIDTH+1-1):0] 			resp_c1_wr_fifo_din = 0;   // header + valid x 2
   logic 						resp_c1_wr_fifo_read;
   logic 						resp_c1_wr_fifo_write = 0;
   logic 						resp_c1_wr_fifo_empty;
   //logic[(`CCI_RX1_HDR_WIDTH+1-1):0]      resp_c1_wr_fifo_dout; // connect to tx_c1_header and valid signals
   logic 						resp_c1_wr_fifo_dout_legal;
   logic 						resp_c1_wr_fifo_almostfull;

   // =========================================================
   // CCI Rule checker 
   // ---------------------------------------------------------
   logic 						cci_rule_checker_flag = 0;
      

   // ================================================================
   // Initialising the CAFU here.
   // ----------------------------------------------------------------
   //              DPI   |             |   CAFU or (SPL + AFU)
   //                  TX|------------>|RX
   //                    |             |
   //                  RX|<------------|TX
   //                    |             |
   // -----------------------------------------------------------------
   cci_std_afu afu_wrapper_inst (
				 /* Link/Protocol (LP) clocks and reset */
				 .vl_clk_LPdomain_32ui             ( clk ),    
				 .ffs_vl_LP32ui_lp2sy_Reset_n      ( resetb ),  
				 .ffs_vl_LP32ui_lp2sy_InitDnForSys ( lp_initdone ),  
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
   
   
   // Reset management
   assign resetb = sys_reset | sw_reset;

   logic [1:0] 						req_fifo_in_rand_ch0;
   logic [1:0] 						req_fifo_in_rand_ch1;
   logic [1:0] 						req_fifo_out_rand_ch0;
   logic [1:0] 						req_fifo_out_rand_ch1;

   always @(posedge clk)
     begin
	req_fifo_in_rand_ch0  = {$random}%2;
	req_fifo_in_rand_ch1  = {$random}%2;

	req_fifo_out_rand_ch0 = {$random}%2;
	req_fifo_out_rand_ch1 = {$random}%2;
     end

   always @(*) begin
      req_c0_fifo_a_din_header = tx_c0_header;
      req_c0_fifo_b_din_header = tx_c0_header;

      if (req_fifo_in_rand_ch0 == 0) begin
	 req_c0_fifo_a_write      = tx_c0_rdvalid;
	 req_c0_fifo_b_write      = 0;
      end
      else begin
	 req_c0_fifo_b_write      = tx_c0_rdvalid;
	 req_c0_fifo_a_write      = 0;
      end
   end

   sbv_gfifo #((`CCI_TX0_HDR_WIDTH), `ASE_FIFO_DEPTH_NUMBITS, 7)
   req_c0_fifo_a (
		  .Resetb      (sys_reset),
		  .Clk         (clk),
		  .fifo_din    (req_c0_fifo_a_din_header),
		  .fifo_wen    (req_c0_fifo_a_write),
		  .fifo_rdack  (req_c0_fifo_a_read),
		  .fifo_dout   (req_c0_fifo_a_dout_header),
		  .fifo_dout_v (req_c0_fifo_a_dout_legal),
		  .fifo_empty  (req_c0_fifo_a_empty),
		  .fifo_full   (),
		  .fifo_count  (),
		  .fifo_almFull(req_c0_fifo_a_almostfull));


   sbv_gfifo #((`CCI_TX0_HDR_WIDTH), `ASE_FIFO_DEPTH_NUMBITS, 7)
   req_c0_fifo_b (
		  .Resetb      (sys_reset),
		  .Clk         (clk),
		  .fifo_din    (req_c0_fifo_b_din_header),
		  .fifo_wen    (req_c0_fifo_b_write),
		  .fifo_rdack  (req_c0_fifo_b_read),
		  .fifo_dout   (req_c0_fifo_b_dout_header),
		  .fifo_dout_v (req_c0_fifo_b_dout_legal),
		  .fifo_empty  (req_c0_fifo_b_empty),
		  .fifo_full   (),
		  .fifo_count  (),
		  .fifo_almFull(req_c0_fifo_b_almostfull));

   always @(*)  begin
      if (req_fifo_out_rand_ch0 == 0) begin
	 if (req_c0_fifo_a_dout_legal == 1) begin
	    req_c0_fifo_a_read = lp_initdone & (resp_c0_rd_fifo_almostfull == 0);
	    req_c0_fifo_b_read = 0;
	 end
	 else begin
	    req_c0_fifo_a_read = 0;
	    req_c0_fifo_b_read = 0;
	 end
	 req_c0_fifo_dout_header = req_c0_fifo_a_dout_header;
	 req_c0_fifo_dout_legal  = req_c0_fifo_a_dout_legal;
      end
      else begin
	 if (req_c0_fifo_b_dout_legal == 1) begin
	    req_c0_fifo_b_read = lp_initdone & (resp_c0_rd_fifo_almostfull == 0);
	    req_c0_fifo_a_read = 0;
	 end
	 else begin
	    req_c0_fifo_b_read = 0;
	    req_c0_fifo_a_read = 0;
	 end
	 req_c0_fifo_dout_header = req_c0_fifo_b_dout_header;
	 req_c0_fifo_dout_legal  = req_c0_fifo_b_dout_legal;
      end
   end


   always @(*) begin
      req_c1_fifo_a_din_header = tx_c1_header;
      req_c1_fifo_a_din_data   = tx_c1_data;
      req_c1_fifo_b_din_header = tx_c1_header;
      req_c1_fifo_b_din_data   = tx_c1_data;

      if (req_fifo_in_rand_ch1 == 0) begin
	 req_c1_fifo_a_write      = tx_c1_wrvalid;
	 req_c1_fifo_b_write      = 0;
      end
      else begin
	 req_c1_fifo_b_write      = tx_c1_wrvalid;
	 req_c1_fifo_a_write      = 0;
      end
   end

   sbv_gfifo #((`CCI_TX1_HDR_WIDTH+`CCI_DATA_WIDTH), `ASE_FIFO_DEPTH_NUMBITS, 7)
   req_c1_fifo_a (
		  .Resetb      (sys_reset),
		  .Clk         (clk),
		  .fifo_din    ({req_c1_fifo_a_din_header,req_c1_fifo_a_din_data}),
		  .fifo_wen    (req_c1_fifo_a_write),
		  .fifo_rdack  (req_c1_fifo_a_read),
		  .fifo_dout   ({req_c1_fifo_a_dout_header,req_c1_fifo_a_dout_data}),
		  .fifo_dout_v (req_c1_fifo_a_dout_legal),
		  .fifo_empty  (req_c1_fifo_a_empty),
		  .fifo_full   (),
		  .fifo_count  (),
		  .fifo_almFull(req_c1_fifo_a_almostfull));

   sbv_gfifo #((`CCI_TX1_HDR_WIDTH+`CCI_DATA_WIDTH), `ASE_FIFO_DEPTH_NUMBITS, 7)
   req_c1_fifo_b (
		  .Resetb      (sys_reset),
		  .Clk         (clk),
		  .fifo_din    ({req_c1_fifo_b_din_header,req_c1_fifo_a_din_data}),
		  .fifo_wen    (req_c1_fifo_b_write),
		  .fifo_rdack  (req_c1_fifo_b_read),
		  .fifo_dout   ({req_c1_fifo_b_dout_header,req_c1_fifo_b_dout_data}),
		  .fifo_dout_v (req_c1_fifo_b_dout_legal),
		  .fifo_empty  (req_c1_fifo_b_empty),
		  .fifo_full   (),
		  .fifo_count  (),
		  .fifo_almFull(req_c1_fifo_b_almostfull));


   always @(*)  begin
      if (req_fifo_out_rand_ch1 == 0) begin
	 if (req_c1_fifo_a_dout_legal) begin
	    req_c1_fifo_a_read = lp_initdone & ((resp_c0_wr_fifo_almostfull == 0) | (resp_c1_wr_fifo_almostfull == 0));
	    req_c1_fifo_b_read = 0;
	 end
	 else begin
	    req_c1_fifo_a_read = 0;
	    req_c1_fifo_b_read = 0;
	 end
	 req_c1_fifo_dout_header = req_c1_fifo_a_dout_header;
	 req_c1_fifo_dout_data   = req_c1_fifo_a_dout_data;
	 req_c1_fifo_dout_legal  = req_c1_fifo_a_dout_legal;
      end
      else begin
	 if (req_c1_fifo_b_dout_legal) begin
	    req_c1_fifo_b_read = lp_initdone & ((resp_c0_wr_fifo_almostfull == 0) | (resp_c1_wr_fifo_almostfull == 0));
	    req_c1_fifo_a_read = 0;
	 end
	 else begin
	    req_c1_fifo_b_read = 0;
	    req_c1_fifo_a_read = 0;
	 end
	 req_c1_fifo_dout_header = req_c1_fifo_b_dout_header;
	 req_c1_fifo_dout_data   = req_c1_fifo_b_dout_data;
	 req_c1_fifo_dout_legal  = req_c1_fifo_b_dout_legal;
      end
   end


   // -----------------------------------------------------------------
   // Issue read request on channel 0 and write request on channel 1
   // Read and write request can be issued simultaneously.
   // -----------------------------------------------------------------

   always @(posedge clk)
     begin
	resp_c0_csr_fifo_write   <= 0;
	resp_c0_csr_fifo_din     <= 0;
	resp_c0_wr_fifo_write    <= 0;
	resp_c0_wr_fifo_din      <= 0;
	resp_c0_rd_fifo_write    <= 0;
	resp_c0_rd_fifo_din      <= 0;
	resp_c1_wr_fifo_write    <= 0;
	resp_c1_wr_fifo_din      <= 0;

	if (lp_initdone) begin
	   buffer_replicator();
	   csr_write_listener();
	   if ((req_c0_fifo_dout_legal == 1) && (resp_c0_rd_fifo_almostfull == 0)) begin
              if (req_c0_fifo_dout_header[55:52] == `ASE_TX0_RDLINE) begin
		 cci_rdline_req(req_c0_fifo_dout_header[45:14], req_c0_fifo_dout_header[13:0]);
              end
	   end

	   if ((req_c1_fifo_dout_legal == 1) && ((resp_c0_wr_fifo_almostfull == 0) || (resp_c1_wr_fifo_almostfull == 0))) begin
              if ((req_c1_fifo_dout_header[55:52] == `ASE_TX1_WRLINE) || (req_c1_fifo_dout_header[55:52] == `ASE_TX1_WRTHRU)) begin
		 cci_wrline_req( req_c1_fifo_dout_header[45:14],  req_c1_fifo_dout_header[13:0], req_c1_fifo_dout_data);
              end
	   end
	end
     end



   sbv_gfifo #((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3), `ASE_FIFO_DEPTH_NUMBITS, 7)
   ase2cafu_csr_ch0_fifo_inst (
			       .Resetb      (sys_reset),
			       .Clk         (clk),
			       .fifo_din    (resp_c0_csr_fifo_din),
			       .fifo_wen    (resp_c0_csr_fifo_write),
			       .fifo_rdack  (resp_c0_csr_fifo_read),
			       .fifo_dout   (resp_c0_csr_fifo_dout),
			       .fifo_dout_v (resp_c0_csr_fifo_dout_legal),
			       .fifo_empty  (resp_c0_csr_fifo_empty),
			       .fifo_full   (),
			       .fifo_count  (),
			       .fifo_almFull(resp_c0_csr_fifo_almostfull));

   // Task takes SW parameters and writes to FIFO
   task cci_ase2cafu_csr_ch0(int resp_type, int mdata, bit [`CCI_DATA_WIDTH-1:0] data);
      begin
	 // If Channel is used for CSR write
	 // Align CSR offset if required (NLB requires Dword align)
	 // Wait for the next rising edge, then apply input
	 if(resp_type == `ASE_RX0_CSR_WRITE) begin
	    $display("SIM-SV: csr_write -> addr = %x, data = %x", mdata[13:2], data[31:0]);
	    resp_c0_csr_fifo_din   <= {data, `ASE_RX0_CSR_WRITE, 2'b00, mdata[13:2], 3'b001};
	    resp_c0_csr_fifo_write   <= 1;
	    if (mdata[13:2] == CCI_RESET_CTRL_ADDR) begin
	       sw_reset <= data[CCI_RESET_CTRL_BITLOC];
	    end
	 end
	 else begin
	    $display("SIM-SV: WARNING-> CSR Response type on CH0 unrecognized !!");
	 end
      end
   endtask


   // ================================================================
   // FIFO DPI -> CAFU CH0 - Read response
   // ----------------------------------------------------------------
   sbv_gfifo #((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3), `ASE_FIFO_DEPTH_NUMBITS, 7)
   ase2cafu_rdResp_ch0_fifo_inst
     (
      .Resetb      (sys_reset),
      .Clk         (clk),
      .fifo_din    (resp_c0_rd_fifo_din),
      .fifo_wen    (resp_c0_rd_fifo_write),
      .fifo_rdack  (resp_c0_rd_fifo_read),
      .fifo_dout   (resp_c0_rd_fifo_dout),
      .fifo_dout_v (resp_c0_rd_fifo_dout_legal),
      .fifo_empty  (resp_c0_rd_fifo_empty),
      .fifo_full   (),
      .fifo_count  (),
      .fifo_almFull(resp_c0_rd_fifo_almostfull)
      );

   // Task takes SW parameters and writes to FIFO
   task cci_ase2cafu_rdResp_ch0(int resp_type, int mdata, bit [`CCI_DATA_WIDTH-1:0] data);
      begin //task
	 // If Channel is used for CSR write
	 // Align CSR offset if required (NLB requires Dword align)
	 // Wait for the next rising edge, then apply input
	 if(resp_type == `ASE_RX0_RD_RESP) begin
	    resp_c0_rd_fifo_din   <= {data, `ASE_RX0_RD_RESP, mdata[13:0], 3'b100};
	    resp_c0_rd_fifo_write <= 1;
	 end
	 else begin
	    $display("SIM-SV: WARNING-> Response type on CH0 unrecognized !!");
	 end
      end
   endtask

   // ================================================================
   // FIFO DPI -> CAFU CH0 - Write response
   // ----------------------------------------------------------------
   sbv_gfifo #((`CCI_DATA_WIDTH+`CCI_RX0_HDR_WIDTH+3), `ASE_FIFO_DEPTH_NUMBITS, 7)
   ase2cafu_wrResp_ch0_fifo_inst (
				  .Resetb      (sys_reset),
				  .Clk         (clk),
				  .fifo_din    (resp_c0_wr_fifo_din),
				  .fifo_wen    (resp_c0_wr_fifo_write),
				  .fifo_rdack  (resp_c0_wr_fifo_read),
				  .fifo_dout   (resp_c0_wr_fifo_dout),
				  .fifo_dout_v (resp_c0_wr_fifo_dout_legal),
				  .fifo_empty  (resp_c0_wr_fifo_empty),
				  .fifo_full   (),
				  .fifo_count  (),
				  .fifo_almFull(resp_c0_wr_fifo_almostfull));

   // Task takes SW parameters and writes to FIFO
   task cci_ase2cafu_wrResp_ch0(int resp_type, int mdata, bit [`CCI_DATA_WIDTH-1:0] data);
      begin
	 // If Channel is used for CSR write
	 // Align CSR offset if required (NLB requires Dword align)
	 // Wait for the next rising edge, then apply input
	 if(resp_type == `ASE_RX0_WR_RESP) begin
	    $display("SIM-SV: Write on channel 0 -> resp = %x, mdata = %x, data = %x", resp_type, mdata[13:2], data[31:0]);
	    resp_c0_wr_fifo_din   <= {data, `ASE_RX0_WR_RESP, mdata[13:0], 3'b010};
	    resp_c0_wr_fifo_write <= 1;
	 end
	 else begin
	    $display("SIM-SV: WARNING-> Write response type on CH0 unrecognized !!");
	 end
      end
   endtask

   // RRS: 6th March 2014
   // capcm_rdline_resp : CA-PCM cacheline read response
   task capcm_rdline_resp(int resp_type, int mdata, bit [`CCI_DATA_WIDTH-1:0] data);
      begin
	 if (ENABLE_CACHING_AGENT_PRIVATE_MEMORY == 1)  begin
	 end
	 else begin
	    $display("SIM-SV: # ERROR # CA-PCM has not been instantiated in simulation.");
	    $display("SIM-SV: See hw/platform.vh for more info");
	    // *FIXME*: Kill simulation here
	 end
      end
   endtask

   // RRS: 6th March 2014
   // capcm_wrline_resp : CA-PCM cacheline write response
   task capcm_wrline_resp(int resp_type, int mdata);
      begin
	 if (ENABLE_CACHING_AGENT_PRIVATE_MEMORY == 1) begin
	 end
	 else begin
	    $display("SIM-SV: # ERROR # CA-PCM has not been instantiated in simulation.");
	    $display("SIM-SV: See hw/platform.vh for more info");
	    // *FIXME*: Kill simulation here
	 end
      end
   endtask


   sbv_gfifo #((`CCI_RX1_HDR_WIDTH+1), `ASE_FIFO_DEPTH_NUMBITS, 7)
   ase2cafu_ch1_fifo_inst (
			   .Resetb      (sys_reset),
			   .Clk         (clk),
			   .fifo_din    (resp_c1_wr_fifo_din),
			   .fifo_wen    (resp_c1_wr_fifo_write),
			   .fifo_rdack  (resp_c1_wr_fifo_read),
			   .fifo_dout   ({rx_c1_header, rx_c1_wrvalid}),
			   .fifo_dout_v (resp_c1_wr_fifo_dout_legal),
			   .fifo_empty  (resp_c1_wr_fifo_empty),
			   .fifo_full   (),
			   .fifo_count  (),
			   .fifo_almFull(resp_c1_wr_fifo_almostfull));

   assign resp_c1_wr_fifo_read = resp_c1_wr_fifo_dout_legal;

   // DPI-C called task
   task cci_ase2cafu_ch1(int resp_type, int mdata);
      begin
	 // Write response returned on CH1
	 if(resp_type == `ASE_RX1_WR_RESP) begin
	    resp_c1_wr_fifo_din   <= {`ASE_RX1_WR_RESP, mdata[13:0], 1'b1};
	    resp_c1_wr_fifo_write <= 1;
	 end
	 else if (resp_type == `ASE_RX0_UMSG) begin
	    resp_c1_wr_fifo_din   <= {`ASE_RX1_WR_RESP, mdata[13:0], 1'b1};
	    resp_c1_wr_fifo_write <= 1;
	 end
	 else begin
	    $display("SIM-SV: WARNING-> Response type on CH1 unrecognized !!");
	 end
      end
   endtask



   logic last_fifo_read;
   always @(posedge clk)
     begin
	last_fifo_read = 0;
	if (resp_c0_rd_fifo_read) begin
	   last_fifo_read = 1;
	end
     end

   // arbitor on channel 0
   always @(*) begin
      resp_c0_csr_fifo_read = 0;
      resp_c0_wr_fifo_read  = 0;
      resp_c0_rd_fifo_read  = 0;
      if (resp_c0_csr_fifo_dout_legal == 1) begin
	 resp_c0_csr_fifo_read = 1;
	 {rx_c0_data, rx_c0_header, rx_c0_rdvalid, rx_c0_wrvalid, rx_c0_cfgvalid} = resp_c0_csr_fifo_dout;
      end
      else if (~resp_c0_csr_fifo_dout_legal & (~resp_c0_wr_fifo_dout_legal | ~last_fifo_read)) begin
	 resp_c0_rd_fifo_read = 1;
	 {rx_c0_data, rx_c0_header, rx_c0_rdvalid, rx_c0_wrvalid, rx_c0_cfgvalid} = resp_c0_rd_fifo_dout;
      end
      else if (~resp_c0_csr_fifo_dout_legal & (~resp_c0_rd_fifo_dout_legal | last_fifo_read)) begin
	 resp_c0_wr_fifo_read = 1;
	 {rx_c0_data, rx_c0_header, rx_c0_rdvalid, rx_c0_wrvalid, rx_c0_cfgvalid} = resp_c0_wr_fifo_dout;
      end
   end




   // ----------------------------------------------------------------
   // Temporary signals
   // ----------------------------------------------------------------
   int 	    intr_id_int;
   int 	    rdline_out;


   // ----------------------------------------------------------------
   // Inactivity management
   // ----------------------------------------------------------------
   int 	    first_transaction_seen = 0;
   int 	    inactivity_counter = 0;
   int 	    any_valid;

   // ----------------------------------------------------------------
   // Inactivity management - Sense first transaction
   // ----------------------------------------------------------------
   assign any_valid =  rx_c0_wrvalid   ||
                       rx_c0_rdvalid   ||
                       rx_c0_cfgvalid  ||
                       rx_c1_wrvalid   ||
                       tx_c0_rdvalid   ||
                       tx_c1_wrvalid;

   // Check for first transaction
   always @(posedge clk, any_valid)
     begin
	if(any_valid) begin
	   first_transaction_seen <= 1;
	end
     end

   // ----------------------------------------------------------------
   // Inactivity management - killswitch
   // ----------------------------------------------------------------
   always @(posedge clk) begin
      if((inactivity_counter==`INACTIVITY_TIMEOUT) && (`INACTIVITY_KILL_ENABLE)) begin
	 $display("SIM-SV: Inactivity timeout reached !!\n");
	 // RRS: Tue Aug 20 13:51:31 PDT 2013
	 start_simkill_countdown();
	 $finish;
      end
   end

   // ----------------------------------------------------------------
   // Inactivity management - counter
   // ----------------------------------------------------------------
   generate
      if (`INACTIVITY_KILL_ENABLE == 1) begin: inactivity_mgmt
	 always @(posedge clk, first_transaction_seen, inactivity_counter) begin
            if(first_transaction_seen) begin
               if(any_valid) begin
		  inactivity_counter = 0;
               end
               else begin
		  inactivity_counter = inactivity_counter + 1;
               end
            end
            else begin
               inactivity_counter = 0;
            end
	 end // always @ (posedge clk, first_transaction_seen, inactivity_counter)
      end
   endgenerate

   // ----------------------------------------------------------------
   // clock process
   // ----------------------------------------------------------------
   initial
     begin
	clk = 0;
	forever #`CLK_TIME clk = ~clk;
     end

   // -----------------------------------------------------------------
   // Initialization Steps
   // - Set signals to known states
   // -----------------------------------------------------------------
   initial begin : ase_entry_point
      $display("SIM-SV: Simulator started...");
      $display("SIM-SV: Sending initial reset...");

      // Initial signal values
      sys_reset = 0;
      #`INITIAL_SYSTEM_RESET_DURATION;
      sys_reset = 1;
      #`INITIAL_SYSTEM_RESET_DURATION;
      ase_init();

      // Setting up CA-private memory
      if (ENABLE_CACHING_AGENT_PRIVATE_MEMORY) begin
	 $display("SIM-SV: Enabling QPI-FPGA Caching Agent Private Memory ");
	 // $display("  Size of CAPCM        = %d bytes", CAPCM_NUM_CACHE_LINES );
	 // $display("  CLAddrWidth of CAPCM = %d bits", CAPCM_CL_ADDR_WIDTH );
	 // capcm_init(CAPCM_NUM_CACHE_LINES);
	 capcm_init(64);
      end

      // Link layer ready signal
      wait (lp_initdone == 1'b1);
      $display("SIM-SV: CCI InitDone is HIGH...");
   end

   // ----------------------------------------------------------------
   // Latency pipe : For LP_InitDone delay
   // This block simulates the latency between a generic reset and QLP
   // Init_Done
   // ----------------------------------------------------------------
   latency_pipe
     #(
       .NUM_DELAY (`LP_INITDONE_READINESS_LATENCY),
       .PIPE_WIDTH (1)
       )
   lp_initdone_lat
     (
      .clk (clk),
      .rst (~resetb),
      .pipe_in (resetb),
      .pipe_out (lp_initdone)
      );


   // ----------------------------------------------------------------
   // Simualtion kill switch
   // ----------------------------------------------------------------
   task simkill();
      begin
	 // CA-PCM deinitialize sequece
	 if (ENABLE_CACHING_AGENT_PRIVATE_MEMORY) begin
	    capcm_deinit();
	 end
	 $display("SIM-SV: Simulation kill command received...");
	 $finish;
      end
   endtask

   // Almost full for cafu2ase ch1 is controlled by FIFO and wrfence requests
   assign tx_c1_almostfull = req_c1_fifo_a_almostfull || req_c1_fifo_b_almostfull;
   assign tx_c0_almostfull = req_c0_fifo_a_almostfull || req_c0_fifo_b_almostfull;


   // ---------------------------------------------------------------
   // CCI rule-checker function
   // ---------------------------------------------------------------
`ifdef CCI_SIMKILL_ON_ILLEGAL_BITS
   // Initial message 
   initial $display("DPI-SV: CCI Signal rule-checker is watching for 'X' and 'Z'");

   // Rule checker function
   // function void cci_rulechecker_func (ref meta, ref data);
   //    logic check_sig;      
   //    begin
   // 	 check_sig = ^meta || ^data;
   // 	 if ((check_sig == `VLOG_UNDEF) || (check_sig == `VLOG_HIIMP)) begin
   // 	    `BEGIN_RED_FONTCOLOR;	    
   // 	    $display("SIM-SV: ASE has detected 'Z' or 'X' were validated by a valid signal.");
   // 	    $display("SIM-SV: @time %d $ meta = %b | data = %b", $time, meta, data);
   // 	    $display("SIM-SV: Simulation will end now");
   // 	    $display("SIM-SV: If 'X' or 'Z' are intentional, define CCI_SIMKILL_ON_ILLEGAL_BITS to '0' in ase_global.vh file");	 
   // 	    `END_RED_FONTCOLOR;	    
   // 	    start_simkill_countdown();	    
   // 	 end	   
   //    end
   // endfunction

   // Rule-checkers
   always @(posedge clk) begin
      if ( tx_c0_rdvalid ) begin
	 //	 cci_rulechecker_func( tx_c0_header[`CCI_TX0_HDR_WIDTH-1:0], 0 );
      end
      if ( tx_c1_wrvalid ) begin
      end
      if ( rx_c0_rdvalid ) begin
      end
      if ( rx_c0_wrvalid ) begin
      end
      if ( rx_c0_cfgvalid ) begin
      end
      if ( rx_c1_wrvalid ) begin
      end
  `ifdef ENABLE_CCI_UMSG_IF
      if ( rx_c0_umsgvalid ) begin
      end
  `endif
  `ifdef ENABLE_CCI_INTR_IF
      if ( tx_c1_intrvalid ) begin
      end
      if ( rx_c0_intrvalid ) begin
      end
      if ( rx_c1_intrvalid ) begin
      end
  `endif
   end
`endif
   
   // ---------------------------------------------------------------
   // If Interrupts and UMsg are not enabled, drive '0' 
   // ---------------------------------------------------------------
`ifndef ENABLE_CCI_INTR_IF
   assign rx_c0_intrvalid = 1'b0;   
   assign rx_c1_intrvalid = 1'b0;   
`endif
`ifndef ENABLE_CCI_UMSG_IF
   assign rx_c0_umsgvalid = 1'b0;   
`endif
                
                
endmodule // cci_mem_translator

