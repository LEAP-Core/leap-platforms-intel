//====================================================================
//
// afu.vh
//
// Original Author : George Powley
// Original Date   : 2014/08/14
//
// Copyright (c) 2014 Intel Corporation
// Intel Proprietary
//
// Description:
// - Common types, structs, and functions used by AFU designs
//
//====================================================================

`ifndef QA_VH
 `define QA_VH

   
 `include "qa_csr.vh"

 localparam QA_DRIVER_DEBUG = 0;


 localparam CACHE_WIDTH = 512;

 // Parameters related to frame buffer sizing.
 localparam QA_ADDR_SZ             = 32;
 localparam QA_ADDR_OFFSET         = 6;
 localparam FRAME_NUMBER           = 128;
 localparam LOG_FRAME_NUMBER       = 7;
 localparam FRAME_CHUNKS           = 64;
 localparam LOG_FRAME_CHUNKS       = 6;
 localparam LOG_FRAME_BASE_POINTER = QA_ADDR_SZ - LOG_FRAME_NUMBER - LOG_FRAME_CHUNKS;

 typedef enum logic [3:0] {WrThru=4'h1, WrLine=4'h2, RdLine=4'h4, WrFence=4'h5} tx_request_t;

 // note: status_array is type bit so it doesn't hold Xs, which cause the status writer to write forever in simulation
 typedef struct 
   {
    logic ready;                      // from writer : 1 = ready for data; 0 = busy, write is ignored
    logic valid;                      // from accel  : data and offset are valid
    logic [CACHE_WIDTH-1:0] data;     // from accel  : data to write
    logic [9:0] offset;               // from accel  : offset into status region
    logic [127:0] afu_id;             // from accel  : unique AFU identifier
    bit   [31:0] status_array [15:0]; // from multiple : status registers
    bit   [15:0] update;              // from multiple : status update request
    logic [31:0] perf_counter;        // from status : common free running counter for reporting performance
  } status_t;

 typedef struct 
   {
    logic is_read;                      // denotes target of read response: 1 for frame_reader, 0 for frame_writer
    logic is_header;                    // denotes a read for header, used by read streamer.
    logic [10:0] rob_addr;              // denotes rob address (data reads)
  } read_metadata_t;

 typedef struct
   {
    logic ready;                     // from accel  : ready for data
    logic valid;                     // from reader : data is valid
    logic [CACHE_WIDTH-1:0] data;    // from reader : data read from memeory
  } reader_bus_t;

 typedef struct
   {
    logic ready;                     // from writer : 1 = ready for data; 0 = busy, write is ignored
    logic valid;                     // from accel  : data is valid
    logic [9:0]             offset;  // from accel  : data to write
    logic [CACHE_WIDTH-1:0] data;    // from accel  : data to write
  } writer_bus_t;

 typedef struct packed
   {
    logic [60:56] byte_enable;
    tx_request_t request_type;
    logic [51:46] rsvd;
    logic [45:14] address;
    logic [13:0]  mdata;
    } tx_header_t;


 typedef struct
   {
    logic request;  
  } channel_req_arb_t;

 typedef struct
   {
      logic reader_grant;
      logic writer_grant;
      logic status_grant;  
   } channel_grant_arb_t;

 typedef struct
   {
    channel_req_arb_t read;
    tx_header_t   read_header;  
    channel_req_arb_t write;
    tx_header_t   write_header;
    logic [511:0] data;
  } frame_arb_t;
    
 
 typedef struct
   {
    tx_header_t  header;
    logic         rdvalid;
    } tx_c0_t;

 typedef struct
   {
    tx_header_t   header;
    logic [511:0] data;
    logic         wrvalid;
    } tx_c1_t;

 typedef struct
   {
    logic [17:0]  header;
    logic [511:0] data;
    logic         wrvalid;
    logic         rdvalid;
    logic         cfgvalid;
    } rx_c0_t;

 typedef struct
   {
    logic [17:0]  header;
    logic         wrvalid;
    } rx_c1_t;

 // Function: Returns physical address for a DSM register
 function automatic [31:0] dsm_offset2addr;
    input    [9:0]  offset_b;
    input    [63:0] base_b;
    begin
       dsm_offset2addr = base_b[37:6] + offset_b[9:6];
    end
 endfunction //

 // Function: Packs read metadata 
 function automatic [12:0] pack_read_metadata;
    input    read_metadata_t metadata;
    begin
       pack_read_metadata = {metadata.is_read, metadata.is_header, metadata.rob_addr};
    end
 endfunction //

 // Function: Packs read metadata 
 function automatic read_metadata_t unpack_read_metadata;
    input    [17:0] metadata;
    begin
       unpack_read_metadata = {is_read: metadata[12], is_header: metadata[11], rob_addr: metadata[10:0]};
    end
 endfunction //


 function automatic header_in_use;
    input    [CACHE_WIDTH-1:0]  header;
    begin
       header_in_use = header[0];
    end
 endfunction //

 function automatic header_chunks;
    input    [CACHE_WIDTH-1:0]  header;
    begin
       header_chunks = header[LOG_FRAME_CHUNKS:1];
    end
 endfunction

`endif //  `ifndef QA_VH

