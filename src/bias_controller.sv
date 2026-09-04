/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2023 Drexel University

// Author       : Sarah Johari (original cnn_layer), refactored for folding
// Date         : May 2026
// File         : bias_controller.sv
// Desc         : Bias storage, gating, and phase selection for folded CNN layer.
//
//   Three functions combined:
//     1. Bias register file: stores one bias value per output channel,
//        writable via bias_wr interface.
//     2. Bias gating: suppresses bias when no input spikes have ever
//        arrived (prevents drift before real input).
//     3. Bias phase mux: selects the P active biases based on phase_cnt
//        (which output channel group is being computed this phase).
//
//   Output: active_bias[P-1:0] — one gated bias per parallel MAC unit.
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module bias_controller #(
    parameter OUT_CHANNEL          = 1,
    parameter IN_CHANNEL           = 1,
    parameter P                    = 4,
    parameter INTEGER_PRECISION    = 7,
    parameter DECIMAL_PRECISION    = 8,
    parameter X_FANIN              = 4,
    parameter Y_FANIN              = 5,

    localparam FANIN       = X_FANIN * Y_FANIN,
    localparam PRECISION   = (1 + INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam OUT_CH_WIDTH= $clog2(OUT_CHANNEL),
    localparam NUM_PHASES  = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1
)(
    input                        rst,
    input                        rst_neuron,
    input                        memclk,
    input                        spkclk,

    // ── bias write interface ──
    input                        bias_wr_en,
    input  [OUT_CH_WIDTH-1:0]    bias_wr_addr,
    input  [PRECISION-1:0]       bias_wr_data,

    // ── input spikes (for gating detection only) ──
    input  [FANIN-1:0]           inspk [IN_CHANNEL-1:0],

    // ── phase selector (from phase_controller) ──
    input  [PHASE_WIDTH-1:0]     phase_cnt,

    // ── output: P gated biases for the active output channel group ──
    output [PRECISION-1:0]       active_bias [P-1:0]
);


    // ─────────────────────────────────────────────────────────────
    // 1. Bias register file — one bias per output channel
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
    // 2. Spike gating — only apply bias when spikes have been seen
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
        if       (rst)         any_input <= 0;
		else if (rst_neuron)    any_input <= 1'b0;
        else if (any_input_raw) any_input <= 1;
    end

    wire [PRECISION-1:0] bias_gated [OUT_CHANNEL-1:0];
    genvar bg;
    generate
        for (bg = 0; bg < OUT_CHANNEL; bg = bg + 1) begin : bias_gate_gen
            assign bias_gated[bg] = any_input ? bias_reg[bg] : '0;
        end
    endgenerate


    // ─────────────────────────────────────────────────────────────
    // 3. Phase mux — select P biases for the active output channels
    //    MAC unit u during phase p → output channel (p * P + u)
    //    Same mux pattern as bram_rd_mux.
    // ─────────────────────────────────────────────────────────────
    reg [PRECISION-1:0] active_bias_r [P-1:0];
    always_comb begin
        for (int u = 0; u < P; u++) begin
            active_bias_r[u] = '0;
            for (int ph = 0; ph < NUM_PHASES; ph++) begin
                if (phase_cnt == ph[PHASE_WIDTH-1:0]) begin
                    if ((ph * P + u) < OUT_CHANNEL)
                        active_bias_r[u] = bias_gated[ph * P + u];
                end
            end
        end
    end

    genvar u;
    generate
        for (u = 0; u < P; u = u + 1) begin : bias_out
            assign active_bias[u] = active_bias_r[u];
        end
    endgenerate

endmodule
