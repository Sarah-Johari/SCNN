/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : May 2026
// File         : bias_store_gated.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Bias storage and spike-gated output for the CNN layer.
//   Provides one learnable bias per output channel, with a gating
//   mechanism that suppresses all biases until at least one input
//   spike has been observed. This prevents LIF neurons from
//   drifting due to bias accumulation before any real input arrives.
//
// ─── Functional Blocks ──────────────────────────────────────────
//
//   1. Bias register file (memclk domain)
//      - OUT_CHANNEL entries, each PRECISION bits wide.
//      - Written via bias_wr_en / bias_wr_addr / bias_wr_data.
//      - All entries cleared to zero on rst.
//
//   2. Spike gating (spkclk domain)
//      - OR-reduces inspk across all spatial positions per channel,
//        then OR-reduces across all IN_CHANNEL channels.
//      - Sticky latch (any_input) latches to 1 on the first spike,
//        remains 1 until rst or rst_neuron clears it.
//      - Output: bias_gated[oc] = any_input ? bias_reg[oc] : 0
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   OUT_CHANNEL          Number of output channels (one bias each)
//   IN_CHANNEL           Number of input channels (for gating detection)
//   INTEGER_PRECISION    Integer bits in fixed-point representation
//   DECIMAL_PRECISION    Fractional bits in fixed-point representation
//   X_FANIN              Input channel height
//   Y_FANIN              Input channel width
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst            Global reset (clears bias_reg and any_input latch)
//   rst_neuron     Neuron reset (clears any_input latch only, biases kept)
//   memclk         Memory clock (bias register writes)
//   spkclk         Spike clock (gating latch)
//   bias_wr_en     Write enable for bias register file
//   bias_wr_addr   Output channel index to write [OUT_CH_WIDTH-1:0]
//   bias_wr_data   Bias value to write [PRECISION-1:0]
//   inspk          Input spikes [IN_CHANNEL][FANIN] — used only for
//                  detecting whether any spike has ever arrived
//   bias_gated     Gated bias output [OUT_CHANNEL][PRECISION] —
//                  zero until first spike, then passes bias_reg values
//
// ─── Reset Behavior ─────────────────────────────────────────────
//
//   rst:         Clears bias_reg to zero AND clears any_input latch.
//   rst_neuron:  Clears any_input latch only. Bias values preserved.
//                Used between inference runs without re-loading biases.
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module bias_store_gated #(
    parameter OUT_CHANNEL          = 1,
    parameter IN_CHANNEL           = 1,
    parameter INTEGER_PRECISION    = 7,
    parameter DECIMAL_PRECISION    = 8,
    parameter X_FANIN              = 4,
    parameter Y_FANIN              = 5,

    localparam FANIN               = X_FANIN * Y_FANIN,
    localparam PRECISION           = (1 + INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam OUT_CH_WIDTH        = $clog2(OUT_CHANNEL)
)(
    input                        rst,
    input                        rst_neuron,
    input                        memclk,
    input                        spkclk,

    // ── bias write interface ──
    input                        bias_wr_en,
    input  [OUT_CH_WIDTH-1:0]    bias_wr_addr,
    input  [PRECISION-1:0]       bias_wr_data,

    // ── input spikes (for gating detection) ──
    input  [FANIN-1:0]           inspk [IN_CHANNEL-1:0],

    // ── output: all gated biases ──
    output [PRECISION-1:0]       bias_gated [OUT_CHANNEL-1:0]
);

    // ─────────────────────────────────────────────────────────────
    // 1. Bias register file
    // ─────────────────────────────────────────────────────────────
    reg [PRECISION-1:0] bias_reg [OUT_CHANNEL-1:0];

    integer b_idx;
    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            for (b_idx = 0; b_idx < OUT_CHANNEL; b_idx = b_idx + 1)
                bias_reg[b_idx] <= 0;
        end else if (bias_wr_en)
            bias_reg[bias_wr_addr] <= bias_wr_data;
    end

    // ─────────────────────────────────────────────────────────────
    // 2. Spike gating
    // ─────────────────────────────────────────────────────────────
    wire [IN_CHANNEL-1:0] inspk_or;
    genvar ai;
    generate
        for (ai = 0; ai < IN_CHANNEL; ai = ai + 1) begin : inspk_or_gen
            assign inspk_or[ai] = |inspk[ai];
        end
    endgenerate
    wire any_input_raw = |inspk_or;

    reg any_input;
    always @(posedge spkclk or posedge rst) begin
        //if (rst | rst_neuron) any_input <= 0;
		if       (rst)          any_input <= 0;
		else if (rst_neuron)    any_input <= 1'b0;
        else if (any_input_raw) any_input <= 1;
    end

    genvar bg;
    generate
        for (bg = 0; bg < OUT_CHANNEL; bg = bg + 1) begin : bias_gate_gen
            assign bias_gated[bg] = any_input ? bias_reg[bg] : '0;
        end
    endgenerate

endmodule
