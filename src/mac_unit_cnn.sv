
/* -----------------------------------------------------------------------------
MIT License
 
Copyright (c) 2026 Drexel University
 
// Author       : Sarah Johari (original bmem_cnn), refactored for folding
// Date         : May 2026
// File         : mac_unit_cnn.sv
// Desc         : MAC (multiply-accumulate) datapath, split out from bmem_cnn.
//
//                Contains:
//                  1. Pipeline registers: rd_en_q (1-cycle delay to align with
//                     BRAM read latency from bram_store_cnn).
//                  2. Partial-sum accumulators: psum[FANOUT], one per spatial
//                     position, with rst_acc clear and rd_en_q gating.
//                  3. Quantized adder: FANOUT instances of qadd that sign-extend
//                     the weight (WT_PRECISION → PRECISION) and add to psum.
//
//                All signals are in the memclk domain. No CDC here.
//                CDC crossing happens later in cnn_layer_folded, after all
//                phases complete and captured_activation is fully populated.
//
//                Instantiated P × IN_CHANNEL times in cnn_layer_folded
//                (shared across output channels via time-multiplexing).
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module mac_unit_cnn #(
    // configurable parameters — same subset as bmem_cnn
    parameter X_FANIN              = 4,           // input height
    parameter Y_FANIN              = 5,           // input width
    parameter X_KERNEL             = 2,           // kernel height
    parameter Y_KERNEL             = 3,           // kernel width
    parameter STRIDE               = 2,           // convolution stride
    parameter INTEGER_PRECISION    = 3,           // integer bits in state vars
    parameter DECIMAL_PRECISION    = 4,           // fractional bits
    parameter WT_INTEGER_PRECISION = 2,           // integer bits in weights

    // local parameters (derived, same formulas as bmem_cnn)
    localparam X_FANOUT      = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT      = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT        =  X_FANOUT * Y_FANOUT,
    localparam WT_PRECISION  = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam PRECISION     = (1 + INTEGER_PRECISION + DECIMAL_PRECISION)
)(
    input                        rst,           // reset
    input                        memclk,        // memory / MAC clock
    //input                        spkclk,        // spike clock (CDC target)

    // ── weight data from bram_store_cnn (via phase mux) ───
    // Already registered inside bram_store_cnn (1-cycle read latency).
    input  [WT_PRECISION-1:0]   rd_data,

    // ── control signals from syn_access_cnn ───────────────
    input  [FANOUT-1:0]         rd_en,         // per-window read enable
    input  [FANOUT-1:0]         rst_acc,       // per-window accumulator reset
    //input  [FANOUT-1:0]         inspk,         // per-window OR'd input spikes

    // ── output: psum in memclk domain (no CDC) ────────────
    //output [FANOUT-1:0]         outspk,        // spike presence per window
    output reg [PRECISION-1:0]      activation [FANOUT-1:0]  // accumulated activation
);

    // ═════════════════════════════════════════════════════════════
    // 1. Pipeline registers — delay inspk and rd_en by 1 cycle
    //    to align with the 1-cycle BRAM read latency of bram_store_cnn.
    // ═════════════════════════════════════════════════════════════
    //reg [FANOUT-1:0] inspk_q;
    reg [FANOUT-1:0] rd_en_q;

    // // delay inspk to be in sync with memory read
    // always @(posedge memclk or posedge rst) begin
    //     if (rst) begin
    //         inspk_q <= 0;
    //     end else begin
    //         inspk_q <= inspk;
    //     end
    // end

    // delay rd_en to capture the correct data from memory
    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            rd_en_q <= 0;
        end else begin
            rd_en_q <= rd_en;
        end
    end


    // ═════════════════════════════════════════════════════════════
    // 2. Partial-sum accumulators — one per spatial position.
    //    psum[i] accumulates sign-extended weights over the kernel sweep.
    //    Reset by rst_acc[i], gated by rd_en_q[i].
    // ═════════════════════════════════════════════════════════════
    reg  [PRECISION-1:0] psum     [FANOUT-1:0];
    wire [PRECISION-1:0] psum_int [FANOUT-1:0];

    genvar i;
    generate
        for (i = 0; i < FANOUT; i = i + 1) begin : psum_reg
            always @(posedge memclk or posedge rst) begin
                if (rst) begin
                    psum[i] <= 0;
                end else begin
                    if (rst_acc[i]) begin
                        psum[i] <= 0;
                    end else begin
                        if (rd_en_q[i]) begin
                            psum[i] <= psum_int[i];
                        end
                    end
                end
            end
        end
    endgenerate


    // ═════════════════════════════════════════════════════════════
    // 3. Quantized adder — sign-extend rd_data from WT_PRECISION
    //    to PRECISION, then add to psum.
    // ═════════════════════════════════════════════════════════════
    localparam INT_PRECISION = PRECISION - WT_PRECISION;

    genvar j;
    generate
        for (j = 0; j < FANOUT; j = j + 1) begin : mac_add
            qadd #(
                .N(PRECISION)
            ) psum_inst (
                .a(psum[j]),
                .b({{INT_PRECISION{rd_data[WT_PRECISION-1]}}, rd_data}),
                .q_result(psum_int[j])
            );
        end
    endgenerate


    // ═════════════════════════════════════════════════════════════
    // 4. Output — psum directly in memclk domain
    //    No CDC here. Clock crossing to spkclk happens in
    //    cnn_layer_folded after all phases complete.
    // ═════════════════════════════════════════════════════════════
    assign activation = psum;

endmodule
