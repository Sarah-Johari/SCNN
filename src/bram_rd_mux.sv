/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author       : Sarah Johari (original cnn_layer), refactored for folding
// Date         : May 2026
// File         : bram_rd_mux.sv
// Desc         : BRAM read-data multiplexer for output-channel folding.
//
//   For each of the P parallel MAC units and each input channel,
//   selects the correct output channel's BRAM rd_data based on
//   the current phase_cnt.
//
//   MAC unit u, input channel c, phase p:
//     → reads from bram_rd_data[p * P + u][c]
//
//   Synthesizes to P × IN_CHANNEL instances of a NUM_PHASES-to-1 mux,
//   each WT_PRECISION bits wide. Cost: a few LUTs per bit.
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module bram_rd_mux #(
    parameter P                    = 4,
    parameter IN_CHANNEL           = 1,
    parameter OUT_CHANNEL          = 1,
    parameter WT_INTEGER_PRECISION = 2,
    parameter DECIMAL_PRECISION    = 4,

    localparam WT_PRECISION = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam NUM_PHASES   = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH  = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1
)(
    // ── phase selector ──
    input  [PHASE_WIDTH-1:0]     phase_cnt,

    // ── all BRAM read outputs (OUT_CHANNEL × IN_CHANNEL) ──
    input  [WT_PRECISION-1:0]    bram_rd_data [OUT_CHANNEL-1:0][IN_CHANNEL-1:0],

    // ── muxed output to MAC units (P × IN_CHANNEL) ──
    output [WT_PRECISION-1:0]    mac_rd_data [P-1:0][IN_CHANNEL-1:0]
);

    genvar u, c;
    generate
        for (u = 0; u < P; u = u + 1) begin : mux_unit
            for (c = 0; c < IN_CHANNEL; c = c + 1) begin : mux_ic
                reg [WT_PRECISION-1:0] muxed_data;
                always_comb begin
                    muxed_data = '0;
                    for (int ph = 0; ph < NUM_PHASES; ph++) begin
                        if (phase_cnt == ph[PHASE_WIDTH-1:0]) begin
                            if ((ph * P + u) < OUT_CHANNEL) begin
                                muxed_data = bram_rd_data[ph * P + u][c];
                            end
                        end
                    end
                end
                assign mac_rd_data[u][c] = muxed_data;
            end
        end
    endgenerate

endmodule
