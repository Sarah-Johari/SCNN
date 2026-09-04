/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Aug 27, 2025
// File         : bram_decoder.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   BRAM write-address decoder for the CNN layer.
//   Given a write enable, input channel index, and output channel
//   index, asserts exactly one bit in the 2D bram_sel array to
//   select which BRAM (out of OUT_CHANNEL × IN_CHANNEL) receives
//   the weight write.
//
//   Used in cnn_layer to route weight programming to the correct
//   bmem_cnn instance.
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   IN_CHANNEL    Number of input channels
//   OUT_CHANNEL   Number of output channels
//
//   Derived (with single-channel guard):
//     IN_CH_WIDTH  = (IN_CHANNEL  <= 1) ? 1 : clog2(IN_CHANNEL)
//     OUT_CH_WIDTH = (OUT_CHANNEL <= 1) ? 1 : clog2(OUT_CHANNEL)
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   en            Write enable — when 0, all bram_sel bits are 0
//   in_ch         Input channel index [IN_CH_WIDTH-1:0]
//   out_ch        Output channel index [OUT_CH_WIDTH-1:0]
//   bram_sel      One-hot selection [OUT_CHANNEL][IN_CHANNEL] —
//                 bram_sel[out_ch][in_ch] = 1 when en is active
//
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module bram_decoder #(
    parameter IN_CHANNEL  = 2,
    parameter OUT_CHANNEL = 3,

    localparam IN_CH_WIDTH     = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL),      
    localparam OUT_CH_WIDTH    = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL)
)(
    input  logic en,
    input  logic [IN_CH_WIDTH-1:0]  in_ch,
    input  logic [OUT_CH_WIDTH-1:0] out_ch,
    output logic [OUT_CHANNEL-1:0][IN_CHANNEL-1:0] bram_sel
);

    always_comb begin
        bram_sel = '0;               // clear all
        if (en)
            bram_sel[out_ch][in_ch] = 1'b1;  // select exactly one BRAM
    end

endmodule
