/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author   	: Anup Das
// Email    	: 
// Date     	: 
// File     	: synchronizer.v
// Desc     	: Two-stage flip-flop synchronizer for clock domain crossing (CDC).
//                Registers an N-bit input through two sequential flip-flop stages
//                on the destination clock domain to reduce metastability risk.
//                Currently outputs from the first stage (in_q1).
 -----------------------------------------------------------------------------*/


`timescale 1ns / 1ps

module synchronizer #(
	//Parameterized values
	parameter N = 8
	)(
	input rst,
	input clk,
	input  [N-1:0]	in,	//input
	output [N-1:0] 	out	//output
	);

	reg [N-1:0] in_q1, in_q2;

	always @(posedge clk or posedge rst) begin
		if (rst) begin
			in_q1 	<= 0;
			in_q2	<= 0;
		end
		else begin
			in_q1	<= in;
			in_q2	<= in_q1;
		end
	end

//	assign out = in_q2;
	assign out = in_q1;

endmodule
