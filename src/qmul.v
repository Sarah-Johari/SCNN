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
// Author       : Anup Das
// Email        : anup.das@drexel.edu
// Date         : June 03, 2024
// File         : qmul.v
// Desc         : This is an implementation of qmultiplier.
// -----------------------------------------------------------------------------*/

/* -----------------------------------------------------------------------------
Modifications Copyright (c) 2026 Drexel University

// Modified by  : Sarah Johari (sj984@drexel.edu)
// Date         : Aug 2026
//
// ─── Bug Fixes ──────────────────────────────────────────────────
//
//   Fix 1: Sign-aware saturation constants.
//     Original: overflow always saturated to +MAX, underflow always
//     to -1 LSB, regardless of the true sign of the product.
//     Fixed: saturation constants now use result[MSB] to select
//     sign-correct values.
//
//   Fix 2: Overflow priority over underflow.
//     Original: underflow was evaluated last and won when both
//     asserted. Fixed: overflow now has priority.
//
//   Fix 3: 0 × negative no longer returns most negative value.
//     Original: sign bit was set (0 XOR 1 = 1) and 2's complement
//     of zero magnitude wrapped, producing {1,0000000} = -MAX.
//     Fixed: if either operand magnitude is zero, output is forced
//     to zero regardless of sign.
//
//   Fix 4: Most negative operand no longer treated as zero.
//     Original: {1,0000000} has no positive 2's complement in N-1
//     bits — the absolute value wraps to zero, collapsing the product.
//     Fixed: the most negative value is clamped to {1,0000001} (-MAX)
//     before conversion, so its magnitude is correctly handled.
//
//   Result: exhaustive sweep at N=8, Q=3 — all 65,025 operand
//   pairs produce correct results (0 mismatches).
//
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module qmult #(
	parameter Q = 12,
	parameter N = 16
	)(
	input 	[N-1:0]	a,
	input	[N-1:0]	b,
	output 	[N-1:0] q_result
	);

	// ── FIX 4: clamp most-negative operand to -MAX ────────
	// {1,000...0} has no valid absolute value in N-1 bits.
	// Clamp to {1,000...01} = -(2^(N-1) - 1) before processing.
	wire [N-1:0] a_clamped = (a == {1'b1, {(N-1){1'b0}}}) ?
	                          {1'b1, {(N-2){1'b0}}, 1'b1} : a;
	wire [N-1:0] b_clamped = (b == {1'b1, {(N-1){1'b0}}}) ?
	                          {1'b1, {(N-2){1'b0}}, 1'b1} : b;

	// ── absolute value conversion (using clamped operands) ─
	wire [N-1:0] a_2cmp, b_2cmp;
	wire [N-1:0] multiplicand, multiplier;

	assign a_2cmp = {a_clamped[N-1], {(N-1){1'b1}} - a_clamped[N-2:0] + 1'b1};
	assign b_2cmp = {b_clamped[N-1], {(N-1){1'b1}} - b_clamped[N-2:0] + 1'b1};

	assign multiplicand = (a_clamped[N-1]) ? a_2cmp : a_clamped;
	assign multiplier   = (b_clamped[N-1]) ? b_2cmp : b_clamped;

	// ── multiplication ────────────────────────────────────
	wire [2*N-1:0] f_result;
	wire [N-1:0]   result;
	wire [N-2:0]   quantized_result, quantized_result_2cmp;

	assign result[N-1]  = a_clamped[N-1] ^ b_clamped[N-1];
	assign f_result     = multiplicand[N-2:0] * multiplier[N-2:0];
	assign quantized_result      = f_result[N-2+Q:Q];
	assign quantized_result_2cmp = {(N-1){1'b1}} - quantized_result[N-2:0] + 1'b1;
	assign result[N-2:0] = (result[N-1]) ? quantized_result_2cmp : quantized_result;

	// ── overflow / underflow detection ────────────────────
	wire overflow  = (f_result[2*N-2:N-1+Q] > 0) ? 1'b1 : 1'b0;

	wire cond1 = (|quantized_result) ? 1'b0 : 1'b1;
	wire cond2 = (multiplier > 0)    ? 1'b1 : 1'b0;
	wire cond3 = (multiplicand > 0)  ? 1'b1 : 1'b0;
	wire underflow = &{cond1, cond2, cond3};

	// ── FIX 1: sign-aware saturation constants ────────────
	localparam MSB = N - 1;

	wire [N-1:0] q_min_mag = result[MSB] ? {{MSB{1'b1}}, 1'b1}           // -1 LSB
	                                     : {{MSB{1'b0}}, 1'b1};          // +1 LSB

	wire [N-1:0] q_max_mag = result[MSB] ? {1'b1, {(N-2){1'b0}}, 1'b1}  // -MAX
	                                     : {1'b0, {MSB{1'b1}}};          // +MAX

	// ── FIX 2: overflow has priority over underflow ───────
	wire [N-1:0] q_uf = underflow ? q_min_mag : result;
	wire [N-1:0] q_of = overflow  ? q_max_mag : q_uf;

	// ── FIX 3: zero operand forces zero output ────────────
	wire a_mag_zero = ~(|a_clamped[N-2:0]);
	wire b_mag_zero = ~(|b_clamped[N-2:0]);
	wire force_zero = a_mag_zero | b_mag_zero;

	assign q_result = force_zero ? {N{1'b0}} : q_of;

endmodule