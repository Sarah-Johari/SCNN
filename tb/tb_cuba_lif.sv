/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : ...
// File         : tb_cuba_lif.sv
// Desc         : Testbench for cuba_lif module (modified, no inspk port).
//
//   1. Write 5 weights to bmem
//   2. Apply input spikes via syn_access_fc
//   3. Observe vmem accumulation and outspk firing
//
//   Parameters: FANIN=5, WT_INTEGER_PRECISION=2
//               → WT_PRECISION=7, PRECISION=8, ADDR_WIDTH=3
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_cuba_lif;

    localparam FANIN                = 5;
    localparam INTEGER_PRECISION    = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_INTEGER_PRECISION = 2;
    localparam WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION;  // 7
    localparam PRECISION            = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;      // 8
    localparam ADDR_WIDTH           = $clog2(FANIN);                                  // 3

    // Clocks
    reg clk_mem = 0;
    reg clk_spk = 0;
    always #5   clk_mem = ~clk_mem;
    always #120 clk_spk = ~clk_spk;

    // Shared signals
    reg                      rst;
    reg                      rst_neuron;
    reg  [FANIN-1:0]         inspk;
    reg  [PRECISION-1:0]     vth;
    reg  [PRECISION-1:0]     decay_rate;
    reg  [PRECISION-1:0]     grow_rate;
    reg  [PRECISION-1:0]     vrest;
    reg  [PRECISION-1:0]     reset_mechanism;
    reg  [PRECISION-1:0]     refractory_period;
    reg                      wr_en;
    reg  [ADDR_WIDTH-1:0]    wr_addr;
    reg  [WT_PRECISION-1:0]  wr_data;

    // syn_access_fc → cuba_lif control signals
    wire                     rst_acc;
    wire                     rd_en;
    wire [ADDR_WIDTH-1:0]    rd_addr;

    // cuba_lif outputs
    wire                     outspk;
    wire [PRECISION-1:0]     vmem;

    // Instantiate syn_access_fc (generates MAC control signals)
    syn_access_fc #(
        .FANIN(FANIN)
    ) sa_dut (
        .rst(rst),
        .memclk(clk_mem),
        .inspk(inspk),
        .rst_acc(rst_acc),
        .rd_en(rd_en),
        .rd_addr(rd_addr)
    );

    // Instantiate cuba_lif (DUT)
    cuba_lif #(
        .FANIN(FANIN),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) dut (
        .rst(rst),
        .rst_neuron(rst_neuron),
        .memclk(clk_mem),
        .spkclk(clk_spk),
        .vth(vth),
        .decay_rate(decay_rate),
        .grow_rate(grow_rate),
        .vrest(vrest),
        .reset_mechanism(reset_mechanism),
        .refractory_period(refractory_period),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_en(rd_en),
        .rd_addr(rd_addr),
        .rst_acc(rst_acc),
        .outspk(outspk),
        .vmem(vmem)
    );

    // Monitor
    always @(posedge clk_spk) begin
        $display("  [%0t] vmem=%0d, outspk=%b", $time, $signed(vmem), outspk);
    end

    initial begin
        $display("=== cuba_lif Test Start ===");

        // Initialize
        rst              = 0;
        rst_neuron       = 0;
        inspk            = '0;
        wr_en            = 0;
        wr_addr          = 0;
        wr_data          = 0;
        vth              = 8'd30;
        decay_rate       = 8'd1;
        grow_rate        = 8'd16;
        vrest            = 8'd0;
        reset_mechanism  = 8'd1;
        refractory_period= 8'd0;

        // Reset
        @(posedge clk_mem);
        rst = 1;
        repeat(3) @(posedge clk_mem);
        repeat(2) @(posedge clk_spk);
        rst = 0;
        repeat(2) @(posedge clk_mem);

        // ── Write weights ────────────────────────────────
        $display("\nWriting 5 weights...");
        for (int i = 0; i < FANIN; i++) begin
            @(posedge clk_mem);
            wr_en   <= 1;
            wr_addr <= i[ADDR_WIDTH-1:0];
            wr_data <= 7'd2;
        end
        @(posedge clk_mem);
        wr_en <= 0;
        repeat(2) @(posedge clk_mem);

        // ── Apply spikes ─────────────────────────────────
        $display("\nApplying spikes: inspk = 5'b10101");
        inspk = 5'b10101;

        // Wait for syn_access_fc sweep + CDC + LIF updates
        repeat(15) @(posedge clk_spk);

        // ── Change spikes ────────────────────────────────
        $display("\nChanging spikes: inspk = 5'b11111");
        inspk = 5'b11111;

        repeat(15) @(posedge clk_spk);

        // ── Remove spikes ────────────────────────────────
        $display("\nRemoving spikes: inspk = 5'b00000");
        inspk = 5'b00000;

        repeat(10) @(posedge clk_spk);

        $display("\n=== cuba_lif Test Completed ===");
        $finish;
    end

endmodule