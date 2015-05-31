//
// Copyright (c) 2015, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.

`ifndef QA_DRV_TYPES
`define QA_DRV_TYPES

//
// Main type definitions for the QA driver.
//

package qa_drv_types;
    import qa_drv_csr_types::*;

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

    typedef enum logic [3:0]
    {
        WrThru=4'h1,
        WrLine=4'h2,
        RdLine=4'h4,
        WrFence=4'h5
    }
    tx_request_t;

    typedef logic [CACHE_WIDTH-1 : 0] t_QA_CACHE_LINE;

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
    }
    status_t;

    typedef struct 
    {
        logic is_read;                      // denotes target of read response: 1 for frame_reader, 0 for frame_writer
        logic is_header;                    // denotes a read for header, used by read streamer.
        logic [10:0] rob_addr;              // denotes rob address (data reads)
    }
    read_metadata_t;

    typedef struct
    {
        logic ready;                     // from accel  : ready for data
        logic valid;                     // from reader : data is valid
        logic [CACHE_WIDTH-1:0] data;    // from reader : data read from memeory
    }
    reader_bus_t;

    typedef struct
    {
        logic ready;                     // from writer : 1 = ready for data; 0 = busy, write is ignored
        logic valid;                     // from accel  : data is valid
        logic [9:0]             offset;  // from accel  : data to write
        logic [CACHE_WIDTH-1:0] data;    // from accel  : data to write
    }
    writer_bus_t;

    typedef struct packed
    {
        logic [60:56] byte_enable;
        tx_request_t request_type;
        logic [51:46] rsvd;
        logic [45:14] address;
        logic [13:0]  mdata;
    }
    tx_header_t;


    typedef struct
    {
        logic request;  
    }
    channel_req_arb_t;

    typedef struct
    {
        logic reader_grant;
        logic writer_grant;
        logic status_grant;  
    }
    channel_grant_arb_t;

    typedef struct
    {
        channel_req_arb_t read;
        tx_header_t   read_header;  
        channel_req_arb_t write;
        tx_header_t   write_header;
        logic [511:0] data;
    }
    frame_arb_t;

    typedef struct
    {
        tx_header_t  header;
        logic         rdvalid;
    }
    tx_c0_t;

    typedef struct
    {
        tx_header_t   header;
        logic [511:0] data;
        logic         wrvalid;
    }
    tx_c1_t;

    typedef struct
    {
        logic [17:0]  header;
        logic [511:0] data;
        logic         wrvalid;
        logic         rdvalid;
        logic         cfgvalid;
    }
    rx_c0_t;

    typedef struct
    {
        logic [17:0]  header;
        logic         wrvalid;
    }
    rx_c1_t;

    // Function: Returns physical address for a DSM register
    function automatic [31:0] dsm_offset2addr;
        input    [9:0]  offset_b;
        input    [63:0] base_b;
        begin
            dsm_offset2addr = base_b[37:6] + offset_b[9:6];
        end
    endfunction

    // Function: Packs read metadata 
    function automatic [12:0] pack_read_metadata;
        input    read_metadata_t metadata;
        begin
            pack_read_metadata = {metadata.is_read, metadata.is_header, metadata.rob_addr};
        end
    endfunction

    // Function: Packs read metadata 
    function automatic read_metadata_t unpack_read_metadata;
        input    [17:0] metadata;
        begin
            unpack_read_metadata.is_read = metadata[12];
            unpack_read_metadata.is_header = metadata[11];
            unpack_read_metadata.rob_addr = metadata[10:0];
        end
    endfunction


    function automatic header_in_use;
        input    [CACHE_WIDTH-1:0]  header;
        begin
            header_in_use = header[0];
        end
    endfunction

    function automatic [LOG_FRAME_CHUNKS - 1:0] header_chunks;
        input    [CACHE_WIDTH-1:0]  header;
        begin
            header_chunks = header[LOG_FRAME_CHUNKS:1];
        end
    endfunction


    // ========================================================================
    //
    //   Debugging --
    //
    //     Each module may declare one or more vectors of debugging state that
    //     are emitted by the status writer in response to CSR triggers.
    //     See status_writer for the mapping of trigger IDs to modules.
    //
    //     Debug requests arrive in CSR_AFU_TRIGGER_DEBUG.  The request value
    //     determines the state written back in status_writer to DSM line 0.
    //
    // ========================================================================

    localparam AFU_DEBUG_REQ_SZ = $bits(t_AFU_DEBUG_REQ);
    localparam AFU_DEBUG_RSP_SZ = 512 - AFU_DEBUG_REQ_SZ;

    typedef logic [AFU_DEBUG_RSP_SZ - 1 : 0] t_AFU_DEBUG_RSP;

endpackage // qa_drv_types

`endif //  `ifndef QA_DRV_TYPES
