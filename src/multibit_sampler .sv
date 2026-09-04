/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Aug 08, 2025
// File         : multibit_sampler.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Single-stage sampling register for an array of multi-bit values.
//   Captures the input array on the rising edge of the destination
//   clock. One clock cycle latency.
//
//   Works correctly because the source signal (psum) is held
//   stable for many destination clock cycles between updates.
//   The destination clock always samples a fully settled value.
//
//   Used in bmem_cnn and bmem_fc to sample psum (activation)
//   from memclk domain onto spkclk domain.
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   N    Bit width of each element
//   M    Number of elements in the array
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst    Async reset (clears register to zero)
//   clk    Destination clock (sampling edge)
//   in     Input array [M] of [N]-bit values (source domain)
//   out    Output array [M] of [N]-bit values (sampled, 1 clk delay)
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module multibit_sampler #(
	//Parameterized values
	parameter N = 8,
	parameter M = 8
	)(
	input rst,
	input clk,
	input  [N-1:0]	in [M-1:0],	//input
	output [N-1:0] 	out [M-1:0]	//output
	);

	reg [N-1:0] in_q1 [M-1:0];
	int i; 

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			for (i = 0; i < M; i++) begin
				in_q1[i] <= '0;
			end
		end
		else begin
			for (i = 0; i < M; i++) begin
				in_q1[i] <= in[i];
			end
		end
	end

	genvar j;
	generate
		for (j = 0; j < M; j++) begin : assign_out
			assign out[j] = in_q1[j];
		end
	endgenerate

endmodule
