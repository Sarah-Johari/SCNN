/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : ...
// File         : tb_syn_access_fc.sv
// Desc         : Testbench for syn_access_fc module (no outspk port).
//
//   1. Apply spike pattern, observe countdown sweep and rd_en gating
//   2. Change pattern, observe rst_acc triggers new sweep
//   3. Remove spikes, observe final sweep
//
//   Parameters: FANIN=5 → ADDR_WIDTH=3
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_syn_access_fc;

    localparam FANIN      = 5;
    localparam ADDR_WIDTH = $clog2(FANIN);

    // Clock
    reg clk = 0;
    always #5 clk = ~clk;

    // DUT signals
    reg                      rst;
    reg  [FANIN-1:0]         inspk;
    wire                     rst_acc;
    wire                     rd_en;
    wire [ADDR_WIDTH-1:0]    rd_addr;

    // Instantiate DUT
    syn_access_fc #(
        .FANIN(FANIN)
    ) dut (
        .rst(rst),
        .memclk(clk),
        .inspk(inspk),
        .rst_acc(rst_acc),
        .rd_en(rd_en),
        .rd_addr(rd_addr)
    );

    // Monitor
    always @(posedge clk) begin
        if (rd_en)
            $display("  [%0t] rd_en=1 | rd_addr=%0d | inspk_q3=%b",
                     $time, rd_addr, dut.inspk_q3);
        if (rst_acc)
            $display("  [%0t] rst_acc fired", $time);
    end

    initial begin
        $display("=== syn_access_fc Test Start ===");

        // Initialize
        inspk = 5'b00000;
        rst   = 1;

        #20;
        rst = 0;

        // ── Test 1: Spikes on positions 0, 3, 4 ─────────
        $display("\nTest 1: inspk = 5'b11001");
        #50; inspk = 5'b11001;

        repeat(20) @(posedge clk);

        // ── Test 2: Change pattern ───────────────────────
        $display("\nTest 2: inspk = 5'b10001");
        inspk = 5'b10001;

        repeat(20) @(posedge clk);

        // ── Test 3: Remove all spikes ────────────────────
        $display("\nTest 3: inspk = 5'b00000");
        inspk = 5'b00000;

        repeat(20) @(posedge clk);

        $display("\n=== syn_access_fc Test Completed ===");
        $finish;
    end

endmodule