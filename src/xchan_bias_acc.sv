/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : May 2026
// File         : xchan_bias_acc.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Cross-channel activation accumulator and bias adder.
//   Sums activations across all IN_CHANNEL input channels for each
//   output channel, then adds a per-channel bias value.
//
//   Purely combinational — no clock, no state. Instantiated once
//   inside cnn_layer (all output channels computed in parallel).
//
// ─── Operation ──────────────────────────────────────────────────
//
//   For each output channel u (0..OUT_CHANNEL-1) and spatial
//   position h (0..FANOUT-1):
//
//     1. Cross-channel sum:
//        acc[u][0][h] = mac_activation[u][0][h]
//        acc[u][f][h] = acc[u][f-1][h] + mac_activation[u][f][h]
//        xc_sum[u][h] = acc[u][IN_CHANNEL-1][h]
//
//     2. Bias addition:
//        xchan_biased[u][h] = xc_sum[u][h] + active_bias[u]
//
//   Resource count:
//     qadd (cross-channel): OUT_CHANNEL × FANOUT × (IN_CHANNEL-1)
//     qadd (bias):          OUT_CHANNEL × FANOUT
//     Total:                OUT_CHANNEL × FANOUT × IN_CHANNEL
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   P                   Set to OUT_CHANNEL (one unit per output channel)
//   IN_CHANNEL          Number of input channels to sum across
//   FANOUT              Number of output spatial positions
//   INTEGER_PRECISION   Integer bits in fixed-point representation
//   DECIMAL_PRECISION   Fractional bits in fixed-point representation
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   mac_activation   Input [OUT_CHANNEL][IN_CHANNEL][FANOUT] of [PRECISION]
//                    per-channel activations from bmem_cnn instances
//   active_bias      Input [OUT_CHANNEL] of [PRECISION]
//                    gated bias from bias_store_gated
//   xchan_biased     Output [OUT_CHANNEL][FANOUT] of [PRECISION]
//                    final activation after cross-channel sum + bias
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module xchan_bias_acc #(
    parameter OUT_CHANNEL       = 1,
    parameter IN_CHANNEL        = 1,
    parameter FANOUT            = 1,
    parameter INTEGER_PRECISION = 7,
    parameter DECIMAL_PRECISION = 8,

    localparam PRECISION = (1 + INTEGER_PRECISION + DECIMAL_PRECISION)
)(
    input  [PRECISION-1:0]  mac_activation [OUT_CHANNEL-1:0][IN_CHANNEL-1:0][FANOUT-1:0],
    input  [PRECISION-1:0]  active_bias [OUT_CHANNEL-1:0],
    output [PRECISION-1:0]  xchan_biased [OUT_CHANNEL-1:0][FANOUT-1:0]
);

    // ── cross-channel accumulation wires ──
    wire [PRECISION-1:0] acc     [OUT_CHANNEL-1:0][IN_CHANNEL-1:0][FANOUT-1:0];
    wire [PRECISION-1:0] xc_sum  [OUT_CHANNEL-1:0][FANOUT-1:0];

    genvar u, h, f;
    generate
        for (u = 0; u < OUT_CHANNEL; u = u + 1) begin : xchan_par
            for (h = 0; h < FANOUT; h = h + 1) begin : xchan_fn

                // First input channel: direct pass-through
                assign acc[u][0][h] = mac_activation[u][0][h];

                // Accumulate remaining input channels
                for (f = 1; f < IN_CHANNEL; f = f + 1) begin : xchan_add
                    qadd #(
                        .N(PRECISION)
                    ) xchan_qadd (
                        .a(acc[u][f-1][h]),
                        .b(mac_activation[u][f][h]),
                        .q_result(acc[u][f][h])
                    );
                end

                // Final cross-channel sum
                assign xc_sum[u][h] = acc[u][IN_CHANNEL-1][h];

                // Add gated bias
                qadd #(
                    .N(PRECISION)
                ) bias_add (
                    .a(xc_sum[u][h]),
                    .b(active_bias[u]),
                    .q_result(xchan_biased[u][h])
                );
            end
        end
    endgenerate

endmodule
