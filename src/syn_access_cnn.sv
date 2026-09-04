/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Jul 23, 2025
// File         : syn_access_cnn.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Read address sequencer and MAC controller for the CNN layer.
//   Generates control signals for bram_store_cnn / bmem_cnn:
//   kernel sweep addresses, per-window read enables, and
//   per-window accumulator resets.
//
//   One instance per input channel in cnn_layer / cnn_layer_folded.
//   Output-channel-agnostic — the same control signals apply to
//   all output channels (in the folded design, the phase controller
//   captures and replays these signals across phases).
//
// ─── Operation ──────────────────────────────────────────────────
//
//   1. Spike delay chain (3 stages on memclk):
//        inspk → inspk_q1 → inspk_q2 → inspk_q3
//
//   2. Change detection:
//        changed_sig = |(inspk_q2 ^ inspk_q3)
//      Any bit difference between q2 and q3 triggers a new sweep.
//
//   3. Per-window rst_acc:
//        rst_acc[win] = changed_sig & (new_nonzero | or_acc)
//      Only windows whose receptive field contains a spike (current
//      or previous pattern) get their accumulator cleared.
//
//   4. FSM (IDLE → STREAMING → DONE → IDLE):
//      When |rst_acc fires, the FSM enters STREAMING.
//      Kernel counter k sweeps 0 → MEM_SIZE-1 (one position per
//      memclk cycle), then DONE returns to IDLE.
//
//   5. Per-window rd_en (combinational, parallel across all windows):
//        rd_en[win] = inspk_q3[input_pixel_for_this_window_at_k]
//      For each output window (wx, wy) and current kernel offset
//      (dx, dy) = (k / Y_KERNEL, k % Y_KERNEL):
//        input_pixel = (wx * STRIDE + dx) * Y_FANIN + (wy * STRIDE + dy)
//        rd_en[win] = 1 if that input pixel has a spike
//      Only active during STREAMING state, zero otherwise.
//
//   6. rd_addr = k (kernel position counter, drives BRAM read address).
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   X_FANIN     Input feature map height
//   Y_FANIN     Input feature map width
//   X_KERNEL    Convolution kernel height
//   Y_KERNEL    Convolution kernel width
//   STRIDE      Convolution stride
//
//   Derived:
//     FANIN          = X_FANIN × Y_FANIN (input spatial positions)
//     X_FANOUT       = ((X_FANIN - X_KERNEL) / STRIDE) + 1
//     Y_FANOUT       = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1
//     FANOUT_FM      = X_FANOUT × Y_FANOUT (output spatial positions)
//     MEM_SIZE       = X_KERNEL × Y_KERNEL (kernel positions to sweep)
//     ADDR_WIDTH_MEM = clog2(MEM_SIZE)
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst        Async reset (clears delay chain, FSM, counter)
//   memclk     Memory clock
//   inspk      Input spikes [FANIN-1:0] — one channel's spike vector
//   rst_acc    Per-window accumulator reset [FANOUT_FM-1:0] — fires
//              when spike pattern changes in that window's receptive field
//   rd_en      Per-window read enable [FANOUT_FM-1:0] — gates MAC
//              accumulation per spatial position per kernel step
//   rd_addr    Kernel read address [ADDR_WIDTH_MEM-1:0] — shared
//              across all windows (0 to MEM_SIZE-1)
//
// ─── Timing ─────────────────────────────────────────────────────
//
//   Spike change detected → rst_acc fires (1 cycle)
//                         → FSM enters STREAMING
//                         → k sweeps 0..MEM_SIZE-1 (MEM_SIZE cycles)
//                         → DONE (1 cycle)
//                         → IDLE
//   Total sweep: MEM_SIZE + 2 cycles from detection to IDLE.
//
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module syn_access_cnn #(
    parameter X_FANIN  = 4,
    parameter Y_FANIN  = 5,
    parameter X_KERNEL = 2,
    parameter Y_KERNEL = 3,
    parameter STRIDE   = 1,

    localparam FANIN          = X_FANIN * Y_FANIN,
    localparam X_FANOUT       = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT       = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT_FM      = X_FANOUT * Y_FANOUT,
    localparam MEM_SIZE       = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM = $clog2(MEM_SIZE)
)(
    input                           rst,
    input                           memclk,
    input      [FANIN-1:0]          inspk,
    // output reg [FANOUT_FM-1:0]      outspk,
    output reg [FANOUT_FM-1:0]      rst_acc,
    output reg [FANOUT_FM-1:0]      rd_en,
    output     [ADDR_WIDTH_MEM-1:0] rd_addr
);

    // ── spike delay chain ─────────────────────────────────
    reg [FANIN-1:0] inspk_q1, inspk_q2, inspk_q3;

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            inspk_q1 <= 0;
            inspk_q2 <= 0;
            inspk_q3 <= 0;
        end else begin
            inspk_q1 <= inspk;
            inspk_q2 <= inspk_q1;
            inspk_q3 <= inspk_q2;
        end
    end

    // ── FSM ───────────────────────────────────────────────
    typedef enum logic [1:0] {IDLE, STREAMING, DONE} state_t;
    state_t state;

    reg [ADDR_WIDTH_MEM-1:0] k;  // shared kernel counter 0→MEM_SIZE-1

    // ── combinational signals ─────────────────────────────
    reg [FANOUT_FM-1:0] rd_en_comb;

    // ── FSM + counter ─────────────────────────────────────
    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            k     <= 0;
        end else begin
            case (state)
                IDLE: begin
                    k     <= 0;
                    if (|rst_acc) begin
                        state <= STREAMING; 
                    end
                end

                STREAMING: begin
                    if (k == MEM_SIZE - 1) begin
                        k     <= 0;
                        state <= DONE;
                    end else begin
                        k <= k + 1;
                    end
                end

                DONE: begin
                    k     <= 0;
                    state <= IDLE;
                end
            endcase
        end
    end

    // ── decode k into (dx, dy) ────────────────────────────
    wire [ADDR_WIDTH_MEM-1:0] dx = k / Y_KERNEL;
    wire [ADDR_WIDTH_MEM-1:0] dy = k % Y_KERNEL;

    // ── parallel rd_en: all windows simultaneously ────────
    integer win_x, win_y, curr_win, input_idx;

    always_comb begin
        rd_en_comb = '0;
        if (state == STREAMING) begin
            for (win_x = 0; win_x < X_FANOUT; win_x++) begin
                for (win_y = 0; win_y < Y_FANOUT; win_y++) begin
                    curr_win  = win_x * Y_FANOUT + win_y;
                    input_idx = (win_x * STRIDE + dx) * Y_FANIN
                            + (win_y * STRIDE + dy);
                    rd_en_comb[curr_win] = inspk_q3[input_idx];
                end
            end
        end
    end

    assign rd_en = rd_en_comb;

    // ── outspk and rst_acc combinational ──────────────────
    logic or_acc, new_nonzero;
    logic changed_sig;
    int   dx2, dy2, curr_win2, addr, base_x, base_y;
    int   win_x2, win_y2;

    assign changed_sig = |(inspk_q2 ^ inspk_q3);

    always_comb begin
        // outspk  = '0;
        rst_acc = '0;
        for (win_x2 = 0; win_x2 < X_FANOUT; win_x2++) begin
            for (win_y2 = 0; win_y2 < Y_FANOUT; win_y2++) begin
                or_acc      = 1'b0;
                new_nonzero = 1'b0;
                curr_win2   = win_x2 * Y_FANOUT + win_y2;
                base_x      = win_x2 * STRIDE;
                base_y      = win_y2 * STRIDE;
                for (dx2 = 0; dx2 < X_KERNEL; dx2++) begin
                    for (dy2 = 0; dy2 < Y_KERNEL; dy2++) begin
                        addr        = (base_x + dx2) * Y_FANIN
                                    + (base_y + dy2);
                        or_acc      |= inspk_q3[addr];
                        new_nonzero |= inspk_q2[addr];
                    end
                end
                // outspk[curr_win2]  = or_acc;
                rst_acc[curr_win2] = changed_sig & (new_nonzero | or_acc);
            end
        end
    end
    assign rd_addr = k;

endmodule