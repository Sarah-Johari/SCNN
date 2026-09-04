/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : ...
// File         : tb_fc_layer.sv
// Desc         : Testbench for fc_layer module.
//
//   1. Write weights to all FANOUT neurons
//   2. Apply input spikes, observe vmem accumulation and outspk
//   3. Change spike pattern, observe re-accumulation
//
//   Parameters: FANIN=5, FANOUT=3, WT_INTEGER_PRECISION=2
//               → WT_PRECISION=7, PRECISION=8
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_fc_layer;

    localparam FANIN                = 5;
    localparam FANOUT               = 3;
    localparam INTEGER_PRECISION    = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_INTEGER_PRECISION = 2;
    localparam WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION;  // 7
    localparam PRECISION            = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;      // 8
    localparam ADDR_WIDTH_FANIN     = $clog2(FANIN);                                  // 3
    localparam ADDR_WIDTH_NEURON    = $clog2(FANOUT);                                 // 2
    localparam FANIN_ENC_BITS       = 12;
    localparam ADDR_WIDTH           = 32;
    localparam NEU_ADDR_START       = FANIN_ENC_BITS;

    // Clocks
    reg clk_mem = 0;
    reg clk_spk = 0;
    always #5   clk_mem = ~clk_mem;
    always #120 clk_spk = ~clk_spk;

    // DUT signals
    reg                      rst;
    reg                      rst_neuron;
    reg  [PRECISION-1:0]     vth;
    reg  [PRECISION-1:0]     decay_rate;
    reg  [PRECISION-1:0]     grow_rate;
    reg  [PRECISION-1:0]     vrest;
    reg  [PRECISION-1:0]     reset_mechanism;
    reg  [PRECISION-1:0]     refractory_period;
    reg                      wr_en;
    reg  [ADDR_WIDTH-1:0]    wr_addr;
    reg  [WT_PRECISION-1:0]  wr_data;
    reg  [FANIN-1:0]         inspk;
    wire [FANOUT-1:0]        outspk;

    // Instantiate DUT
    fc_layer #(
        .FANIN(FANIN),
        .FANOUT(FANOUT),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NEU_ADDR_START(NEU_ADDR_START)
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
        .inspk(inspk),
        .outspk(outspk)
    );

    initial begin
        $display("=== fc_layer Test Start ===");

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

        // ── Write weights (all = 2) for all neurons ──────
        $display("\nWriting weights (all = 2)...");
        for (int n = 0; n < FANOUT; n++) begin
            for (int f = 0; f < FANIN; f++) begin
                @(posedge clk_mem);
                wr_en   <= 1;
                wr_addr <= '0;
                wr_addr[ADDR_WIDTH_FANIN-1:0]                    <= f[ADDR_WIDTH_FANIN-1:0];
                wr_addr[NEU_ADDR_START +: ADDR_WIDTH_NEURON]     <= n[ADDR_WIDTH_NEURON-1:0];
                wr_data <= 7'd2;
            end
        end
        @(posedge clk_mem);
        wr_en <= 0;
        $display("  Done. Wrote %0d weights.", FANOUT * FANIN);

        // ── Apply spikes ─────────────────────────────────
        $display("\nApplying spikes: inspk = 5'b10101 (3 active)");
        inspk = 5'b10101;

        repeat(15) @(posedge clk_spk);
        $display("  outspk = %b", outspk);

        // ── Change spikes ────────────────────────────────
        $display("\nChanging spikes: inspk = 5'b11111 (all active)");
        inspk = 5'b11111;

        repeat(15) @(posedge clk_spk);
        $display("  outspk = %b", outspk);

        // ── Remove spikes ────────────────────────────────
        $display("\nRemoving spikes: inspk = 5'b00000");
        inspk = 5'b00000;

        repeat(10) @(posedge clk_spk);
        $display("  outspk = %b", outspk);

        $display("\n=== fc_layer Test Completed ===");
        $finish;
    end

endmodule