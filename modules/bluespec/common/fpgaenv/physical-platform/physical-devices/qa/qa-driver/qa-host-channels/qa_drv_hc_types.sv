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

//
// Main type definitions for the QA host channel driver.
//

package qa_drv_hc_types;
    localparam QA_DRIVER_DEBUG = 0;

    import qa_driver_csr_types::*;
    import cci_mpf_if_pkg::*;

    //
    // Cache line as a vector of 32 bit objects
    //
    localparam N_BIT32_PER_CACHE_LINE = CCI_CLDATA_WIDTH / 32;
    typedef logic [N_BIT32_PER_CACHE_LINE-1 : 0][31:0] t_cci_cldata_vec32;


    //
    // FIFO ring buffer indices.  This is the only place the buffer sizes
    // are defined.  The hardware will tell the software the sizes during
    // initialization.
    //
    // Indices indicate the line within a buffer relative to a buffer's
    // base address.
    //
    typedef logic [12:0] t_fifo_to_host_idx;
    typedef logic [12:0] t_fifo_from_host_idx;


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
    t_read_metadata;

    typedef struct
    {
        logic request;  
    }
    t_channel_req_arb;

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
    t_channel_grant_arb;

    typedef struct
    {
        t_channel_req_arb read;
        t_cci_ReqMemHdr   readHeader;  
        t_channel_req_arb write;
        t_cci_ReqMemHdr   writeHeader;
        t_cci_cldata      data;
    }
    t_frame_arb;


    //
    // DSM addressing.
    //
    typedef logic [3:0] t_dsm_line_offset;

    // Function: Returns physical address for a DSM register
    function automatic [31:0] dsm_line_offset_to_addr;
        input    t_dsm_line_offset offset_l;
        input    [63:0] base_b;
        begin
            dsm_line_offset_to_addr = base_b[37:6] + offset_l;
        end
    endfunction


    // Function: Packs read metadata 
    function automatic [12:0] pack_read_metadata;
        input    t_read_metadata metadata;
        begin
            pack_read_metadata = { metadata.reserved,
                                   metadata.isHeader,
                                   metadata.isRead,
                                   metadata.robAddr };
        end
    endfunction

    // Function: Packs read metadata 
    function automatic t_read_metadata unpack_read_metadata;
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

    localparam AFU_DEBUG_REQ_SZ = $bits(t_afu_debug_req);
    localparam AFU_DEBUG_RSP_SZ = 512 - AFU_DEBUG_REQ_SZ;

    typedef logic [AFU_DEBUG_RSP_SZ - 1 : 0] t_afu_debug_rsp;


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
    typedef logic [31:0] t_sreg_addr;
    typedef logic [63:0] t_sreg;

    //
    // FIFO from host status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Index of the next line the FPGA will read when data is present.
        t_fifo_from_host_idx oldestReadLineIdx;

        // Debugging state
        t_afu_debug_rsp dbgFIFOState;
    }
    t_to_status_mgr_fifo_from_host;
    
    typedef struct
    {
        // Index of the most recent line written by the host.
        t_fifo_from_host_idx newestReadLineIdx;
    }
    t_from_status_mgr_fifo_from_host;


    //
    // FIFO to host status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Index of the next ring buffer position that will be written by the FPGA.
        t_fifo_to_host_idx nextWriteIdx;
    }
    t_to_status_mgr_fifo_to_host;

    typedef struct
    {
        // Index of the oldest position still unread by the host.
        t_fifo_to_host_idx oldestWriteIdx;
    }
    t_from_status_mgr_fifo_to_host;


    //
    // Tester status.  All fields must be valid every cycle.
    //
    typedef struct
    {
        // Debugging state
        t_afu_debug_rsp dbgTester;
    }
    t_to_status_mgr_tester;

endpackage // qa_drv_hc_types

