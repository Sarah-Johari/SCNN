/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author   	: Sarah Johari
// Email    	: sj984@drexel.edu
// Date     	: Aug 08, 2025
// File     	: synchronizer2.sv
// Desc     	: Two-stage flip-flop synchronizer for clock domain crossing (CDC).
//                Registers M parallel N-bit vectors through two sequential flip-flop
//                stages on the destination clock domain to reduce metastability risk.
//                Currently outputs from the first stage (in_q1).
 -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module synchronizer2 #(
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
	reg [N-1:0] in_q2 [M-1:0];
	int i; 

	always_ff @(posedge clk or posedge rst) begin
		if (rst) begin
			for (i = 0; i < M; i++) begin
				in_q1[i] <= '0;
				in_q2[i]  <= '0;
			end
		end
		else begin
			for (i = 0; i < M; i++) begin
				in_q1[i] <= in[i];
				in_q2[i] <= in_q1[i];
			end
		end
	end

	genvar j;
	generate
		for (j = 0; j < M; j++) begin : assign_out
//			assign out[j] = in_q2[j];
			assign out[j] = in_q1[j];
		end
	endgenerate

endmodule
