//
// Copyright (c) 2016, Intel Corporation
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

`ifndef CCI_MPF_CSRS_VH
`define CCI_MPF_CSRS_VH

`include "cci_csr_if.vh"
import cci_mpf_csrs_pkg::*;

//
// MPF implements a single CSR read/write module that connects to the host
// through MMIO reads and writes.  A single module is more efficient, since
// MMIO lacks flow control and requires message buffering.  The CCI MPF CSRs
// interface defines a set of signals that are managed by the CSR module.
// Private modports are defined for each class of MPF shims.
//
//   *** Directions are relative to a shim ***
//

interface cci_mpf_csrs();

    //
    // VTP -- virtual to physical translation
    //

    // Input: page table mode (see cci_mpf_csrs.h)
    t_cci_mpf_vtp_csr_mode vtp_in_mode;
    // Input: page table base address (line address)
    t_cci_clAddr vtp_in_page_table_base;
    logic        vtp_in_page_table_base_valid;

    // Events: these wires fire to indicate an event. The CSR shim sums
    // events into counters.
    logic vtp_out_event_4kb_hit;
    logic vtp_out_event_4kb_miss;
    logic vtp_out_event_2mb_hit;
    logic vtp_out_event_2mb_miss;
    logic vtp_out_event_pt_walk_busy;


    //
    // VC MAP -- Mapping eVC_VA to real physical channels.
    //
    logic [63:0] vc_map_ctrl;
    logic        vc_map_ctrl_valid;


    //
    // WRO -- write/read ordering
    //

    // Output: total writes observed
    logic [63:0] wro_out_num_writes;
    // Output: total reads observed
    logic [63:0] wro_out_num_reads;
    // Output: total write conflicts (writes blocked)
    logic [63:0] wro_out_num_write_conflicts;
    // Output: total read conflicts (reads blocked by writes)
    logic [63:0] wro_out_num_read_conflicts;

    // CSR manager port
    modport csr
       (
        output vtp_in_mode,
        output vtp_in_page_table_base,
        output vtp_in_page_table_base_valid,

        output vc_map_ctrl,
        output vc_map_ctrl_valid,

        input  wro_out_num_writes,
        input  wro_out_num_reads,
        input  wro_out_num_write_conflicts,
        input  wro_out_num_read_conflicts
        );
    modport csr_events
       (
        input vtp_out_event_4kb_hit,
        input vtp_out_event_4kb_miss,
        input vtp_out_event_2mb_hit,
        input vtp_out_event_2mb_miss,
        input vtp_out_event_pt_walk_busy
        );

    modport vtp
       (
        input  vtp_in_mode,
        input  vtp_in_page_table_base,
        input  vtp_in_page_table_base_valid
        );
    modport vtp_events
       (
        output vtp_out_event_4kb_hit,
        output vtp_out_event_4kb_miss,
        output vtp_out_event_2mb_hit,
        output vtp_out_event_2mb_miss,
        output vtp_out_event_pt_walk_busy
        );

    modport vc_map
       (
        input  vc_map_ctrl,
        input  vc_map_ctrl_valid
        );

    modport wro
       (
        output wro_out_num_writes,
        output wro_out_num_reads,
        output wro_out_num_write_conflicts,
        output wro_out_num_read_conflicts
        );

endinterface // cci_mpf_csrs

`endif
