/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2023 Drexel University

// Author       : Sarah Johari (original), wrapper for folding A/B comparison
// Date         : May 2026
// File         : cnn_layer_wrapper.sv
// Desc         : Compile-time wrapper that selects between the original
//                cnn_layer and the output-channel-folded cnn_layer_folded.
//
//   USE_FOLDING = 0 → synthesizes original cnn_layer (zero overhead)
//   USE_FOLDING = 1 → synthesizes cnn_layer_folded with P parallel units
//
//   The generate-if is resolved at elaboration time. Only one design
//   exists in the netlist — the other is never synthesized.
//
//   Port list is the superset of both modules. When USE_FOLDING = 0,
//   phase_done is tied to 1'b1 (always complete, no gating needed).
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

`include "defines.vh"

module cnn_layer_wrapper #(
    // ── configuration parameters (same as both cnn_layer variants) ──
    parameter X_FANIN              = 4,
    parameter Y_FANIN              = 5,
    parameter X_KERNEL             = 2,
    parameter Y_KERNEL             = 3,
    parameter STRIDE               = 1,
    parameter IN_CHANNEL           = 1,
    parameter OUT_CHANNEL          = 1,
    parameter POOL_X_KERNEL        = 1,
    parameter POOL_Y_KERNEL        = 1,
    parameter POOL_STRIDE          = 1,
    parameter POOL_MODE            = 1,
    parameter IN_CH_ADDR_START     = 1,
    parameter OUT_CH_ADDR_START    = 1,
    parameter FANIN_ENC_BITS       = 12,
    parameter INTEGER_PRECISION    = 7,
    parameter DECIMAL_PRECISION    = 8,
    parameter WT_INTEGER_PRECISION = 2,
    parameter ADDR_WIDTH           = 32,
    // ── folding control ──
    parameter USE_FOLDING          = 0,   // 0 = original, 1 = folded
    parameter P                    = 4,   // folding factor (only used when USE_FOLDING = 1)
    parameter Q                    = 4,

    // ── derived (same as both modules) ──
    localparam MEM_SIZE        = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM  = $clog2(MEM_SIZE),
    localparam X_FANOUT        = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT        = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT          = X_FANOUT * Y_FANOUT,
    localparam FANIN           = X_FANIN * Y_FANIN,
   localparam IN_CH_WIDTH     = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL),      
    localparam OUT_CH_WIDTH    = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL),
    localparam WT_PRECISION    = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam PRECISION       = (1 + INTEGER_PRECISION + DECIMAL_PRECISION)
)(
    input  rst,
    input  rst_neuron,
    input  memclk,
    input  spkclk,
    // neuron parameters
    input  [PRECISION-1:0] vth,
    input  [PRECISION-1:0] decay_rate,
    input  [PRECISION-1:0] grow_rate,
    input  [PRECISION-1:0] vrest,
    input  [PRECISION-1:0] reset_mechanism,
    input  [PRECISION-1:0] refractory_period,
    // weight write interface
    input  wr_en,
    input  [ADDR_WIDTH-1:0] wr_addr,
    input  [WT_PRECISION-1:0] wr_data,
    // bias write interface
    input  bias_wr_en,
    input  [OUT_CH_WIDTH-1:0] bias_wr_addr,
    input  [PRECISION-1:0] bias_wr_data,
    // spike I/O
    input  [FANIN-1:0] inspk [IN_CHANNEL-1:0],
    // outputs
    output [PRECISION-1:0] vmem [OUT_CHANNEL-1:0][FANOUT-1:0],
    output [FANOUT-1:0]    outspk [OUT_CHANNEL-1:0],
    // folding handshake (tied to 1 when USE_FOLDING = 0)
    output phase_done
);

    generate
        // ─────────────────────────────────────────────────────
        // USE_FOLDING = 0 → original cnn_layer (zero overhead)
        // ─────────────────────────────────────────────────────
        if (USE_FOLDING == 0) begin : original

            // phase_done not needed — always report "done"
            assign phase_done = 1'b1;

            cnn_layer #(
                .X_FANIN(X_FANIN),
                .Y_FANIN(Y_FANIN),
                .X_KERNEL(X_KERNEL),
                .Y_KERNEL(Y_KERNEL),
                .POOL_X_KERNEL(POOL_X_KERNEL),
                .POOL_Y_KERNEL(POOL_Y_KERNEL),
                .STRIDE(STRIDE),
                .POOL_STRIDE(POOL_STRIDE),
                .POOL_MODE(POOL_MODE),
                .IN_CHANNEL(IN_CHANNEL),
                .OUT_CHANNEL(OUT_CHANNEL),
                .IN_CH_ADDR_START(IN_CH_ADDR_START),
                .OUT_CH_ADDR_START(OUT_CH_ADDR_START),
                .INTEGER_PRECISION(INTEGER_PRECISION),
                .DECIMAL_PRECISION(DECIMAL_PRECISION),
                .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) layer_inst (
                .rst(rst),
                .rst_neuron(rst_neuron),
                .memclk(memclk),
                .spkclk(spkclk),
                .vth(vth),
                .decay_rate(decay_rate),
                .grow_rate(grow_rate),
                .vrest(vrest),
                .reset_mechanism(reset_mechanism),
                .refractory_period(refractory_period),
                .wr_en(wr_en),
                .wr_addr(wr_addr),
                .wr_data(wr_data),
                .bias_wr_en(bias_wr_en),
                .bias_wr_addr(bias_wr_addr),
                .bias_wr_data(bias_wr_data),
                .inspk(inspk),
                .vmem(vmem),
                .outspk(outspk)
            );

        // ─────────────────────────────────────────────────────
        // USE_FOLDING = 1 → folded cnn_layer_folded with P units
        // ─────────────────────────────────────────────────────
        end else begin : folded

            cnn_layer_folded_shared #(
                .X_FANIN(X_FANIN),
                .Y_FANIN(Y_FANIN),
                .X_KERNEL(X_KERNEL),
                .Y_KERNEL(Y_KERNEL),
                .POOL_X_KERNEL(POOL_X_KERNEL),
                .POOL_Y_KERNEL(POOL_Y_KERNEL),
                .STRIDE(STRIDE),
                .POOL_STRIDE(POOL_STRIDE),
                .POOL_MODE(POOL_MODE),
                .IN_CHANNEL(IN_CHANNEL),
                .OUT_CHANNEL(OUT_CHANNEL),
                .IN_CH_ADDR_START(IN_CH_ADDR_START),
                .OUT_CH_ADDR_START(OUT_CH_ADDR_START),
                .INTEGER_PRECISION(INTEGER_PRECISION),
                .DECIMAL_PRECISION(DECIMAL_PRECISION),
                .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
                .ADDR_WIDTH(ADDR_WIDTH),
                .P(P),
                .Q(Q)
            ) layer_inst (
                .rst(rst),
                .rst_neuron(rst_neuron),
                .memclk(memclk),
                .spkclk(spkclk),
                .vth(vth),
                .decay_rate(decay_rate),
                .grow_rate(grow_rate),
                .vrest(vrest),
                .reset_mechanism(reset_mechanism),
                .refractory_period(refractory_period),
                .wr_en(wr_en),
                .wr_addr(wr_addr),
                .wr_data(wr_data),
                .bias_wr_en(bias_wr_en),
                .bias_wr_addr(bias_wr_addr),
                .bias_wr_data(bias_wr_data),
                .inspk(inspk),
                .vmem(vmem),
                .outspk(outspk),
                .phase_done(phase_done)
            );

        end
    endgenerate

endmodule
