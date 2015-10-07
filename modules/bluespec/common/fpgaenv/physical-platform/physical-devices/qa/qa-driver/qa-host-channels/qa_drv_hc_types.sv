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

`ifndef QA_DRV_HC_TYPES
`define QA_DRV_HC_TYPES

`include "qa_driver.vh"

//
// Main type definitions for the QA host channel driver.
//

package qa_drv_hc_types;
    localparam QA_DRIVER_DEBUG = 0;

    import qa_driver_types::*;
    import qa_driver_csr_types::*;

    typedef t_TX_HEADER_CCI_S t_TX_HEADER;

    //
    // Cache line data types.
    //
    localparam QA_ADDR_SZ = 32;
    localparam QA_CACHE_LINE_SZ = 512;

    typedef logic [QA_CACHE_LINE_SZ-1 : 0] t_CACHE_LINE;

    // Most memory accesses use the address of a line
    typedef logic [QA_ADDR_SZ-1 : 0] t_CACHE_LINE_ADDR;

    // Cache line as a vector of 8 bit objects
    localparam N_BIT8_PER_CACHE_LINE = QA_CACHE_LINE_SZ / 8;
    typedef logic [N_BIT8_PER_CACHE_LINE-1 : 0][7:0] t_CACHE_LINE_VEC8;
    localparam N_BYTES_PER_CACHE_LINE = N_BIT8_PER_CACHE_LINE;

    // Cache line as a vector of 16 bit objects
    localparam N_BIT16_PER_CACHE_LINE = QA_CACHE_LINE_SZ / 16;
    typedef logic [N_BIT16_PER_CACHE_LINE-1 : 0][15:0] t_CACHE_LINE_VEC16;

    // Cache line as a vector of 32 bit objects
    localparam N_BIT32_PER_CACHE_LINE = QA_CACHE_LINE_SZ / 32;
    typedef logic [N_BIT32_PER_CACHE_LINE-1 : 0][31:0] t_CACHE_LINE_VEC32;

    // Cache line as a vector of 64 bit objects
    localparam N_BIT64_PER_CACHE_LINE = QA_CACHE_LINE_SZ / 64;
    typedef logic [N_BIT64_PER_CACHE_LINE-1 : 0][31:0] t_CACHE_LINE_VEC64;


    //
    // FIFO ring buffer indices.  This is the only place the buffer sizes
    // are defined.  The hardware will tell the software the sizes during
    // initialization.
    //
    // Indices indicate the line within a buffer relative to a buffer's
    // base address.
    //
    typedef logic [12:0] t_FIFO_TO_HOST_IDX;
    typedef logic [12:0] t_FIFO_FROM_HOST_IDX;


    //
    // Read metadata is passed in the mdata field of each read request in
    // order to reorder and route the response.
    //
    typedef struct 
    {
        logic reserved;             // Used by MUX that merges the channels
                                    // and the direct memory reader.
        logic isHeader;             // Read header, used to manage FIFO credits
        logic isRead;               // Target of read response
        logic [9:0] robAddr;        // ROB address (data reads)
    }
    t_READ_METADATA;

    typedef struct
    {
        logic request;  
    }
    t_CHANNEL_REQ_ARB;

    typedef struct
    {
        logic readerGrant;
        logic writerGrant;
        logic statusGrant;  

        // Can issue indicates whether the channel is blocked due to flow
        // control.  No request will be granted during cycles when canIssue
        // is false, though clients are not obligated to check this field.
        logic canIssue;
    }
    t_CHANNEL_GRANT_ARB;

    typedef struct
    {
        t_CHANNEL_REQ_ARB read;
        t_TX_HEADER   readHeader;  
        t_CHANNEL_REQ_ARB write;
        t_TX_HEADER   writeHeader;
        logic [511:0] data;
    }
    t_FRAME_ARB;

    typedef struct
    {
        t_TX_HEADER  header;
        logic        rdvalid;
    }
    t_TX_C0;

    typedef struct
    {
        t_TX_HEADER   header;
        logic [511:0] data;
        logic         wrvalid;
    }
    t_TX_C1;

    typedef struct
    {
        logic [17:0]  header;
        logic [511:0] data;
        logic         wrvalid;
        logic         rdvalid;
        logic         cfgvalid;
    }
    t_RX_C0;

    typedef struct
    {
        logic [17:0]  header;
        logic         wrvalid;
    }
    t_RX_C1;


    //
    // DSM addressing.
    //
    typedef logic [3:0] t_DSM_LINE_OFFSET;

    // Function: Returns physical address for a DSM register
    function automatic [31:0] dsm_line_offset_to_addr;
        input    t_DSM_LINE_OFFSET offset_l;
        input    [63:0] base_b;
        begin
            dsm_line_offset_to_addr = base_b[37:6] + offset_l;
        end
    endfunction


    // Function: Packs read metadata 
    function automatic [12:0] pack_read_metadata;
        input    t_READ_METADATA metadata;
        begin
            pack_read_metadata = { metadata.reserved,
                                   metadata.isHeader,
                                   metadata.isRead,
                                   metadata.robAddr };
        end
    endfunction

    // Function: Packs read metadata 
    function automatic t_READ_METADATA unpack_read_metadata;
        input    [17:0] metadata;
        begin
            unpack_read_metadata.reserved = metadata[12];
            unpack_read_metadata.isHeader = metadata[11];
            unpack_read_metadata.isRead = metadata[10];
            unpack_read_metadata.robAddr = metadata[9:0];
        end
    endfunction


    // ========================================================================
    //
    //   Debugging --
    //
    //     Each module may declare one or more vectors of debugging state that
    //     are emitted by the status writer in response to CSR triggers.
    //     See status_manager for the mapping of trigger IDs to modules.
    //
    //     Debug requests arrive in CSR_AFU_TRIGGER_DEBUG.  The request value
    //     determines the state written back in status_manager to DSM line 0.
    //
    // ========================================================================

    localparam AFU_DEBUG_REQ_SZ = $bits(t_AFU_DEBUG_REQ);
    localparam AFU_DEBUG_RSP_SZ = 512 - AFU_DEBUG_REQ_SZ;

    typedef logic [AFU_DEBUG_RSP_SZ - 1 : 0] t_AFU_DEBUG_RSP;


    // ========================================================================
    //
    //   Status manager --
    //
    //     Modules may communicate with the status manager in order to write
    //     state back to the host and consume updates from the host.
    //     Both FIFOs connected to the host manage credits and ring buffer
    //     pointer updates through the status manager.
    //
    // ========================================================================
    
    // Status registers, exposed as a debugging interface to read status
    // from the FPGA-side client.
    typedef logic [31:0] t_SREG_ADDR;
    typedef logic [63:0] t_SREG;

    //
    // FIFO from host status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Index of the next line the FPGA will read when data is present.
        t_FIFO_FROM_HOST_IDX oldestReadLineIdx;

        // Debugging state
        t_AFU_DEBUG_RSP dbgFIFOState;
    }
    t_TO_STATUS_MGR_FIFO_FROM_HOST;
    
    typedef struct
    {
        // Index of the most recent line written by the host.
        t_FIFO_FROM_HOST_IDX newestReadLineIdx;
    }
    t_FROM_STATUS_MGR_FIFO_FROM_HOST;


    //
    // FIFO to host status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Index of the next ring buffer position that will be written by the FPGA.
        t_FIFO_TO_HOST_IDX nextWriteIdx;
    }
    t_TO_STATUS_MGR_FIFO_TO_HOST;

    typedef struct
    {
        // Index of the oldest position still unread by the host.
        t_FIFO_TO_HOST_IDX oldestWriteIdx;
    }
    t_FROM_STATUS_MGR_FIFO_TO_HOST;


    //
    // Tester status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Debugging state
        t_AFU_DEBUG_RSP dbgTester;
    }
    t_TO_STATUS_MGR_TESTER;

endpackage // qa_drv_types

`endif //  `ifndef QA_DRV_HC_TYPES
