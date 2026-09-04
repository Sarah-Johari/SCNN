/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : ...
// File         : tb_syn_access_cnn.sv
// Desc         : Testbench for syn_access_cnn module.
//
//   Test 1: Apply spike pattern, observe FSM sweep (IDLE→STREAMING→DONE)
//   Test 2: Change spikes, observe second sweep triggers
//   Test 3: Remove all spikes, observe sweep on falling edges
//
//   Parameters: X_FANIN=4, Y_FANIN=5, X_KERNEL=2, Y_KERNEL=3, STRIDE=1
//               → FANIN=20, FANOUT=9, MEM_SIZE=6
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_syn_access_cnn;

    localparam X_FANIN     = 4;
    localparam Y_FANIN     = 5;
    localparam X_KERNEL    = 2;
    localparam Y_KERNEL    = 3;
    localparam STRIDE      = 1;
    localparam FANIN       = X_FANIN * Y_FANIN;                        // 20
    localparam X_FANOUT    = ((X_FANIN - X_KERNEL) / STRIDE) + 1;      // 3
    localparam Y_FANOUT    = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;      // 3
    localparam FANOUT      = X_FANOUT * Y_FANOUT;                       // 9
    localparam MEM_SIZE    = X_KERNEL * Y_KERNEL;                        // 6
    localparam ADDR_WIDTH_MEM = $clog2(MEM_SIZE);                        // 3

    // Clock
    reg memclk = 0;
    always #5 memclk = ~memclk;

    // DUT signals
    reg                        rst;
    reg  [FANIN-1:0]           inspk;
    wire [FANOUT-1:0]          outspk;
    wire [FANOUT-1:0]          rst_acc;
    wire [FANOUT-1:0]          rd_en;
    wire [ADDR_WIDTH_MEM-1:0]  rd_addr;

    // Instantiate DUT
    syn_access_cnn #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE)
    ) dut (
        .rst(rst),
        .memclk(memclk),
        .inspk(inspk),
        .outspk(outspk),
        .rst_acc(rst_acc),
        .rd_en(rd_en),
        .rd_addr(rd_addr)
    );

    // Monitor FSM and key outputs
    always @(posedge memclk) begin
        if (dut.state == 1)
            $display("  [%0t] STREAMING k=%0d: rd_en=%b, rd_addr=%0d",
                     $time, dut.k, rd_en, rd_addr);
        if (|rst_acc)
            $display("  [%0t] rst_acc=%b", $time, rst_acc);
    end

    initial begin
        $display("=== syn_access_cnn Test Start ===");
        $display("FANIN=%0d, FANOUT=%0d, MEM_SIZE=%0d\n", FANIN, FANOUT, MEM_SIZE);

        // Initialize
        rst   = 0;
        inspk = '0;

        // Reset
        @(posedge memclk);
        rst = 1;
        @(posedge memclk);
        rst = 0;

        // ── Test 1: Spikes at (0,0) and (1,1) ───────────
        $display("Test 1: Set spikes at (0,0) and (1,1)");
        inspk = '0;
        inspk[0*Y_FANIN + 0] = 1'b1;
        inspk[1*Y_FANIN + 1] = 1'b1;

        repeat(15) @(posedge memclk);
        $display("  outspk = %b\n", outspk);

        // ── Test 2: Change spikes — add (2,3), remove (0,0)
        $display("Test 2: Add (2,3), remove (0,0)");
        inspk[0*Y_FANIN + 0] = 1'b0;
        inspk[2*Y_FANIN + 3] = 1'b1;

        repeat(15) @(posedge memclk);
        $display("  outspk = %b\n", outspk);

        // ── Test 3: Remove all spikes ────────────────────
        $display("Test 3: Remove all spikes");
        inspk = '0;

        repeat(15) @(posedge memclk);
        $display("  outspk = %b", outspk);

        $display("\n=== syn_access_cnn Test Completed ===");
        $finish;
    end

endmodule