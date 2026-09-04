/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2023 Drexel Distributed, Intelligent, and Scalable COmputing (DISCO) Lab

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
// Author   	: Sarah Johari
// Email    	: sj984@drexel.edu
// Date     	: Jul 07, 2025
// File     	: pooling.v
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module pooling #(
    parameter X_FANIN           = 3,
    parameter Y_FANIN           = 3,
    parameter POOL_X_KERNEL     = 2,
    parameter POOL_Y_KERNEL     = 2,
    parameter POOL_STRIDE       = 2,
    parameter OUT_CHANNEL       = 1,
    parameter POOL_MODE         = 0,   // 0 = MAX, 1 = MIN, 2 = NO POOLING
    parameter INTEGER_PRECISION = 7,
    parameter DECIMAL_PRECISION = 8,


    localparam PRECISION        = 1 + INTEGER_PRECISION + DECIMAL_PRECISION,
    localparam FANIN            = X_FANIN * Y_FANIN,
    localparam X_FANOUT         = ((X_FANIN - POOL_X_KERNEL) / POOL_STRIDE) + 1,
    localparam Y_FANOUT         = ((Y_FANIN - POOL_Y_KERNEL) / POOL_STRIDE) + 1,
    localparam FANOUT           = X_FANOUT * Y_FANOUT
    // localparam POOL_SIZE        = POOL_X_KERNEL * POOL_Y_KERNEL
)(
    input                  clk,
    input                  rst,
    input  [PRECISION-1:0] activation_in  [OUT_CHANNEL-1:0][FANIN-1:0],
    // input  [FANIN-1:0]     spk_in,
    output [PRECISION-1:0] activation_out [OUT_CHANNEL-1:0][FANOUT-1:0]
    // output [FANOUT-1:0]    spk_out
);

    // // ── qadd wires for MEAN pooling ───────────────────────
    // wire [PRECISION-1:0] pool_acc [OUT_CHANNEL-1:0][FANOUT-1:0][POOL_SIZE-1:0];
    // wire [PRECISION-1:0] pool_sum [OUT_CHANNEL-1:0][FANOUT-1:0];

    // genvar ch_g, wx_g, wy_g, p_g;
    // generate
    //     for (ch_g = 0; ch_g < OUT_CHANNEL; ch_g++) begin
    //         for (wx_g = 0; wx_g < X_FANOUT; wx_g++) begin
    //             for (wy_g = 0; wy_g < Y_FANOUT; wy_g++) begin

    //                 localparam curr_win_g = wx_g * Y_FANOUT + wy_g;

    //                 // first element — no adder needed
    //                 assign pool_acc[ch_g][curr_win_g][0] =
    //                     activation_in[ch_g][(wx_g * POOL_STRIDE) * Y_FANIN
    //                                        + (wy_g * POOL_STRIDE)];

    //                 // chain qadd for remaining elements
    //                 for (p_g = 1; p_g < POOL_SIZE; p_g++) begin
    //                     localparam dx_l = p_g / POOL_Y_KERNEL;
    //                     localparam dy_l = p_g % POOL_Y_KERNEL;
    //                     qadd #(
    //                         .N(PRECISION)
    //                     ) qadd_mean (
    //                         .a(pool_acc[ch_g][curr_win_g][p_g-1]),
    //                         .b(activation_in[ch_g][(wx_g * POOL_STRIDE + dx_l) * Y_FANIN
    //                                                + (wy_g * POOL_STRIDE + dy_l)]),
    //                         .q_result(pool_acc[ch_g][curr_win_g][p_g])
    //                     );
    //                 end

    //                 // final sum after chain
    //                 assign pool_sum[ch_g][curr_win_g] = pool_acc[ch_g][curr_win_g][POOL_SIZE-1];

    //             end
    //         end
    //     end
    // endgenerate

    // ── combinational signals ─────────────────────────────
    logic [PRECISION-1:0] activation_comb [OUT_CHANNEL-1:0][FANOUT-1:0];
    // logic [FANOUT-1:0]    spk_comb;
    // integer               winner_idx      [FANOUT-1:0];
	
	  generate
        // ─────────────────────────────────────────────────
        // POOL_MODE = 0 → MAX pooling
        // ─────────────────────────────────────────────────
        if (POOL_MODE == 0) begin : max_pool
 
            integer ch, wx, wy, dx, dy;
            integer curr_win, input_idx;
 
            always_comb begin
                for (ch = 0; ch < OUT_CHANNEL; ch++) begin
                    for (wx = 0; wx < X_FANOUT; wx++) begin
                        for (wy = 0; wy < Y_FANOUT; wy++) begin
                            curr_win = wx * Y_FANOUT + wy;
                            // init to most negative value
                            activation_comb[ch][curr_win] = {1'b1, {(PRECISION-1){1'b0}}};
                            for (dx = 0; dx < POOL_X_KERNEL; dx++) begin
                                for (dy = 0; dy < POOL_Y_KERNEL; dy++) begin
                                    input_idx = (wx * POOL_STRIDE + dx) * Y_FANIN
                                              + (wy * POOL_STRIDE + dy);
                                    if ($signed(activation_in[ch][input_idx]) >
                                        $signed(activation_comb[ch][curr_win])) begin
                                        activation_comb[ch][curr_win] = activation_in[ch][input_idx];
                                    end
                                end
                            end
                        end
                    end
                end
            end
 
        // ─────────────────────────────────────────────────
        // POOL_MODE = 1 → MIN pooling
        // ─────────────────────────────────────────────────
        end else if (POOL_MODE == 1) begin : min_pool
 
            integer ch, wx, wy, dx, dy;
            integer curr_win, input_idx;
 
            always_comb begin
                for (ch = 0; ch < OUT_CHANNEL; ch++) begin
                    for (wx = 0; wx < X_FANOUT; wx++) begin
                        for (wy = 0; wy < Y_FANOUT; wy++) begin
                            curr_win = wx * Y_FANOUT + wy;
                            // init to most positive value
                            activation_comb[ch][curr_win] = {1'b0, {(PRECISION-1){1'b1}}};
                            for (dx = 0; dx < POOL_X_KERNEL; dx++) begin
                                for (dy = 0; dy < POOL_Y_KERNEL; dy++) begin
                                    input_idx = (wx * POOL_STRIDE + dx) * Y_FANIN
                                              + (wy * POOL_STRIDE + dy);
                                    if ($signed(activation_in[ch][input_idx]) <
                                        $signed(activation_comb[ch][curr_win])) begin
                                        activation_comb[ch][curr_win] = activation_in[ch][input_idx];
                                    end
                                end
                            end
                        end
                    end
                end
            end
 
        // ─────────────────────────────────────────────────
        // POOL_MODE = 2 → NO pooling (passthrough)
        //   Zero combinational logic. Just wires.
        //   FANIN must equal FANOUT (kernel=1, stride=1).
        // ─────────────────────────────────────────────────
        end else begin : no_pool
 
            always_comb begin
                for (int ch = 0; ch < OUT_CHANNEL; ch++)
                    for (int w = 0; w < FANOUT; w++)
                        activation_comb[ch][w] = activation_in[ch][w];
            end
 
        end
    endgenerate
	

        // // ── spike pooling ─────────────────────────────────
        // spk_comb = '0;
        // for (wx = 0; wx < X_FANOUT; wx++) begin
        //     for (wy = 0; wy < Y_FANOUT; wy++) begin
        //         curr_win = wx * Y_FANOUT + wy;

        //         case (POOL_MODE)

        //             // ── MAX: spike of winner element ──────
        //             0: spk_comb[curr_win] = spk_in[winner_idx[curr_win]];

        //             // ── MIN: spike of winner element ──────
        //             1: spk_comb[curr_win] = spk_in[winner_idx[curr_win]];

        //             // ── MEAN: OR all spikes in window ─────
        //             2: begin
        //                 for (dx = 0; dx < POOL_X_KERNEL; dx++) begin
        //                     for (dy = 0; dy < POOL_Y_KERNEL; dy++) begin
        //                         input_idx = (wx * POOL_STRIDE + dx) * Y_FANIN
        //                                   + (wy * POOL_STRIDE + dy);
        //                         spk_comb[curr_win] |= spk_in[input_idx];
        //                     end
        //                 end
        //             end

        //             // ── NO POOLING: passthrough ───────────
        //             3: spk_comb[curr_win] = spk_in[curr_win];

        //             default: spk_comb[curr_win] = '0;

        //         endcase
        //     end
        // end


    // ── 1-cycle delay register ────────────────────────────
    logic [PRECISION-1:0] activation_reg [OUT_CHANNEL-1:0][FANOUT-1:0];
    // logic [FANOUT-1:0]    spk_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int c = 0; c < OUT_CHANNEL; c++)
                for (int w = 0; w < FANOUT; w++)
                    activation_reg[c][w] <= '0;
            // spk_reg <= '0;
        end else begin
            activation_reg <= activation_comb;
            // spk_reg        <= spk_comb;
        end
    end

    assign activation_out = activation_reg;
    // assign spk_out        = spk_reg;

endmodule
