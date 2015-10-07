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

`include "qa_drv_hc.vh"

//
// Test node that is always inserted between the driver top and the FIFO
// channels to the host.  In its normal state the tester simply lets messages
// flow between the two.  By setting a CSR the tester can be configured
// into source, sink and loopback modes.
//

module qa_drv_hc_tester
  #(
    parameter CCI_DATA_WIDTH = 512,
    parameter CCI_RX_HDR_WIDTH = 18,
    parameter CCI_TX_HDR_WIDTH = 61,
    parameter CCI_TAG_WIDTH = 13
    )
   (
    input logic clk,
    input logic resetb,

    input   t_CSR_AFU_STATE        csr,

    // To-client FIFO
    output logic [CCI_DATA_WIDTH-1:0] rx_fifo_data,
    output logic                      rx_fifo_rdy,
    input  logic                      rx_fifo_enable,

    // From-client FIFO
    input  logic [CCI_DATA_WIDTH-1:0] tx_fifo_data,
    output logic                      tx_fifo_rdy,
    input  logic                      tx_fifo_enable,

    // Internal wires for to-client FIFO
    input  logic [CCI_DATA_WIDTH-1:0] rx_data,
    input  logic                      rx_rdy,
    output logic                      rx_enable,

    // Internal wires for from-client FIFO
    output logic [CCI_DATA_WIDTH-1:0] tx_data,
    input  logic                      tx_rdy,
    output logic                      tx_enable,

    output t_TO_STATUS_MGR_TESTER tester_to_status
    );

    typedef logic [CCI_DATA_WIDTH-1:0] t_DATA;

    //
    // Test mode.
    //
    typedef enum logic [1:0]
    {
        NORMAL,
        SINK,
        SOURCE,
        LOOPBACK
    }
    t_STATE;

    t_STATE state;

    // SOURCE state
    logic [30:0] source_count;

    // Signal completed operation
    logic test_done;

    //
    // Move data around, with route depending on state.
    //
    always_comb
    begin
        test_done = 0;

        // Normal data connection passes RX/TX wires between client
        // and FIFO channels.
        rx_fifo_data = rx_data;
        tx_data = tx_fifo_data;

        case (state)
          SINK:
            begin
                //
                // SINK:  Consume all messages in both directions.
                //
                //   The data wires remain wired as normal since they are
                //   don't cares.
                //
                rx_fifo_rdy = 1'b0;             // Disable client
                rx_enable = rx_rdy && tx_rdy;   // Sink!

                // Done if bit 0 of received data is 1
                test_done = (rx_enable && (rx_data[0] == 1'b1));

                tx_fifo_rdy = 1'b0;             // Disable client
                tx_enable = test_done;          // Send one message when the test
                                                // ends.
            end

          SOURCE:
            begin
                //
                // SOURCE:  Send messages continuously to host.
                //
                rx_fifo_rdy = 1'b0;             // Disable client
                rx_enable = rx_rdy;             // Sink incoming

                // Done if count of messages to send is 0
                test_done = (tx_rdy && (source_count == 1));

                // Put a counter in the low bits and signal the last message
                // by setting bit 0 to 1 iff last
                tx_data[31:0] = { source_count, (source_count == 1) };

                tx_fifo_rdy = 1'b0;             // Disable client
                tx_enable = tx_rdy;
            end

          LOOPBACK:
            begin
                //
                // LOOPBACK:  Send all messages from host back to host.
                //
                rx_fifo_rdy = 1'b0;             // Disable client
                rx_enable = rx_rdy && tx_rdy;   // Accept a new message if it
                                                // can be transmitted back.

                // Done if bit 0 of received data is 1
                test_done = (rx_enable && (rx_data[0] == 1'b1));

                tx_data[31:0] = rx_data[31:0];  // Loopback low bits
                tx_fifo_rdy = 1'b0;             // Disable client
                tx_enable = rx_enable;
            end

          default:
            begin
                //
                // Normal mode.  Connect the client to the driver.
                //
                rx_fifo_rdy = rx_rdy;
                rx_enable = rx_fifo_enable;

                tx_fifo_rdy = tx_rdy && csr.afu_en_user_channel;
                tx_enable = tx_fifo_enable;
            end
        endcase
    end


    //
    // Update source data when in SOURCE mode.
    //
    always_ff @(posedge clk)
    begin
        if (state != SOURCE)
        begin
            source_count <= csr.afu_enable_test.count;
        end
        else if (tx_rdy)
        begin
            source_count <= source_count - 1;
        end
    end


    //
    // Detect testing requests (CSR writes).
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            state <= NORMAL;
        end
        else
        begin
            //
            // The CSR manager holds afu_enable_test with the value of the
            // request for one cycle.
            //
            if (csr.afu_enable_test.test_state != 0)
            begin
                state <= t_STATE'(csr.afu_enable_test.test_state);
            end
            else if (test_done)
            begin
                // End testing
                state <= NORMAL;
            end
        end
    end


    //
    // Debugging state.
    //
    always_ff @(posedge clk)
    begin
        if (! resetb)
        begin
            tester_to_status.dbgTester <= 0;
        end
        else
        begin
            tester_to_status.dbgTester[5:0] <= { rx_rdy, rx_enable, tx_rdy, tx_enable, state };
        end
    end

endmodule // qa_driver
