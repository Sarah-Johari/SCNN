/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : ...
// File         : tb_bmem_cnn.sv
// Desc         : Testbench for bmem_cnn module (activation-only, no inspk/outspk).
//
//   Test 1: Write 6 weights, sweep rd_addr with rd_en=all, verify accumulation
//   Test 2: rst_acc clears all accumulators
//   Test 3: Selective rd_en=0101, only windows 0,2 accumulate
//
//   Parameters: X_FANIN=4, Y_FANIN=5, X_KERNEL=2, Y_KERNEL=3,
//               STRIDE=2, WT_INTEGER_PRECISION=2
//               → FANOUT=4, MEM_SIZE=6, WT_PRECISION=7, PRECISION=8
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_bmem_cnn;

    // Parameters (match the DUT exactly)
    localparam X_FANIN              = 4;
    localparam Y_FANIN              = 5;
    localparam X_KERNEL             = 2;
    localparam Y_KERNEL             = 3;
    localparam STRIDE               = 2;
    localparam INTEGER_PRECISION    = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_INTEGER_PRECISION = 2;
    localparam X_FANOUT             = ((X_FANIN - X_KERNEL) / STRIDE) + 1;
    localparam Y_FANOUT             = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;
    localparam FANOUT               = X_FANOUT * Y_FANOUT;           // 4
    localparam MEM_SIZE             = X_KERNEL * Y_KERNEL;            // 6
    localparam ADDR_WIDTH           = $clog2(MEM_SIZE);               // 3
    localparam WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION;  // 7
    localparam PRECISION            = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;      // 8

    // Clocks
    reg memclk = 0;
    reg spkclk = 0;
    always #5   memclk = ~memclk;
    always #120 spkclk = ~spkclk;

    // DUT signals
    reg                       rst;
    reg                       wr_en;
    reg  [ADDR_WIDTH-1:0]     wr_addr;
    reg  [WT_PRECISION-1:0]   wr_data;
    reg  [FANOUT-1:0]         rd_en;
    reg  [ADDR_WIDTH-1:0]     rd_addr;
    reg  [FANOUT-1:0]         rst_acc;
    wire [PRECISION-1:0]      activation [FANOUT-1:0];

    // Instantiate DUT
    bmem_cnn #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION)
    ) dut (
        .rst(rst),
        .memclk(memclk),
        .spkclk(spkclk),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rst_acc(rst_acc),
        .activation(activation)
    );

    initial begin
        $display("=== bmem_cnn Test Start ===");

        // Initialize
        rst     = 0;
        wr_en   = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_en   = 0;
        rd_addr = 0;
        rst_acc = 0;

        // Reset
        @(posedge memclk);
        rst = 1;
        @(posedge memclk);
        rst = 0;

        // ── Write 6 weights (all = 1) ────────────────────
        $display("Writing 6 weights (all = 1)...");
        for (int k = 0; k < MEM_SIZE; k++) begin
            @(posedge memclk);
            wr_en   <= 1;
            wr_addr <= k[ADDR_WIDTH-1:0];
            wr_data <= 7'd1;
        end
        @(posedge memclk);
        wr_en <= 0;

        // ── Test 1: Accumulate, rd_en=all, sweep rd_addr ─
        $display("\nTest 1: Accumulate with rd_en=1111");
        rst_acc = {FANOUT{1'b1}};
        @(posedge memclk);
        rst_acc = 0;

        for (int k = 0; k < MEM_SIZE; k++) begin
            @(posedge memclk);
            rd_addr <= k[ADDR_WIDTH-1:0];
            rd_en   <= {FANOUT{1'b1}};
        end
        @(posedge memclk);
        rd_en <= 0;

        // Wait for CDC
        repeat(4) @(posedge spkclk);
        $display("  activation: [%0d, %0d, %0d, %0d]",
                 activation[0], activation[1], activation[2], activation[3]);

        // ── Test 2: rst_acc clears ───────────────────────
        $display("\nTest 2: rst_acc clears accumulators");
        rst_acc = {FANOUT{1'b1}};
        @(posedge memclk);
        rst_acc = 0;

        repeat(4) @(posedge spkclk);
        $display("  activation: [%0d, %0d, %0d, %0d]",
                 activation[0], activation[1], activation[2], activation[3]);

        // ── Test 3: Selective rd_en=0101 ─────────────────
        $display("\nTest 3: Selective rd_en=0101");
        for (int k = 0; k < 3; k++) begin
            @(posedge memclk);
            rd_addr <= k[ADDR_WIDTH-1:0];
            rd_en   <= 4'b0101;
        end
        @(posedge memclk);
        rd_en <= 0;

        repeat(4) @(posedge spkclk);
        $display("  activation: [%0d, %0d, %0d, %0d]",
                 activation[0], activation[1], activation[2], activation[3]);

        $display("\n=== bmem_cnn Test Completed ===");
        $finish;
    end

endmodule