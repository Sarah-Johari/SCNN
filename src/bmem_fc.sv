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
// Date         : Feb 05, 2024
// File         : bmem.v
// Desc         : This is an implementation of a 1D array of memory.
//                This array holds the synaptic memory of all incoming
//                connections to a neuron. Block RAM is used to implement
//                synaptic memory (configured via defines.vh). The
//                implementation consists of pipelined memory access using
//                a fast clock. Memory contents are accessed one at a time.
// Changes      : 1.1. Added more options to implement synaptic memory
//                     (BRAM, URAM, Distributed, Register, Auto).
//                2.1. Complete redesign: address generator placed outside.
//                     Module implements 1) synaptic memory and
//                     2) multiply-accumulate. Outputs are double flip-flop
//                     synchronized to spkclk.
// -----------------------------------------------------------------------------*/

/* -----------------------------------------------------------------------------
Modifications Copyright (c) 2026 Drexel University

// Modified by  : Sarah Johari (sj984@drexel.edu)
// Date         : 2025
// File         : bmem_fc.sv
//
// ─── Modifications ──────────────────────────────────────────────
//
//   1. Added WT_INTEGER_PRECISION parameter.
//      Original: WT_PRECISION = 1 + DECIMAL_PRECISION (sign + fraction).
//      Modified: WT_PRECISION = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION
//      (configurable integer bits in weights).
//
//   2. Removed inspk port and inspk_q pipeline register.
//      Original: inspk delayed by 1 cycle (inspk_q), CDC-crossed to
//      spkclk as outspk for the LIF neuron.
//      Modified: not needed — LIF operates in activation-only mode.
//
//   3. Removed outspk port and its CDC synchronizer.
//      Original: outspk = CDC-crossed inspk_q (spike presence in spkclk).
//      Modified: not used downstream (LIF.inspk tied to 0).
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module bmem_fc #(
	//configurable parameters
	parameter FANIN 		= 256,	//FANIN of the neuron
	parameter INTEGER_PRECISION 	= 3,	//integer precision
	parameter WT_INTEGER_PRECISION =2,
	parameter DECIMAL_PRECISION	= 4,	//decimal precision

	//local parameters
	localparam WT_PRECISION = (1+WT_INTEGER_PRECISION+DECIMAL_PRECISION),			//precision of synaptic weights
	localparam PRECISION 	= (1+INTEGER_PRECISION+DECIMAL_PRECISION),	//precision of state variables (= 1 + integer_precision + decimal_precision)
	localparam ADDR_WIDTH 	= $clog2(FANIN)	//address width for the memory addresses of fanin of each neuron. 
)(
	input rst,				//reset
	input memclk,				//memory access & mac clock
	input spkclk,				//spike clock
	input wr_en,				//write enable for writing to the synaptic weight memory
	input [ADDR_WIDTH-1:0] wr_addr,		//synaptic memory address for write
	input [WT_PRECISION-1:0] wr_data,	//synaptic weight
	input rd_en,				//read enable for reading from synaptic weight memory
	input [ADDR_WIDTH-1:0] rd_addr,		//synaptic memory address for read
	input rst_acc,				//reset for the accumulator
	output [PRECISION-1:0] activation	//output activation to the LIF module
);

	reg [WT_PRECISION-1:0] rd_data;
	// reg inspk_q; 
	reg rd_en_q;

	//instantiate the memory
	(* ram_style = "block" *) reg [WT_PRECISION-1:0] mem [FANIN-1:0];

	//access the memory
	always @(posedge memclk) begin
		if (wr_en) begin
			mem[wr_addr] <= wr_data;
		end
		rd_data <= mem[rd_addr];
	end


	//delay the read enable to capture the correct data from the memory
	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			rd_en_q <= 0;
		end
		else begin
			rd_en_q <= rd_en;
		end
	end

	//mac operation
	reg [PRECISION-1:0] psum;
	wire [PRECISION-1:0] psum_int;

	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			psum <= 0;
		end
		else begin
			if (rst_acc) begin
				psum <= 0;
			end
			else begin
				if (rd_en_q) begin
					psum <= psum_int;
				end
			end
		end
	end

	//quantized adder
	localparam INT_PRECISION = PRECISION - WT_PRECISION;

	qadd #(
		.N(PRECISION)
	) psum_inst(
		.a(psum),
		.b({ {INT_PRECISION{rd_data[WT_PRECISION-1]}},rd_data }),
		.q_result(psum_int)
	);

	//output assignment
	// localparam PRECISION_PLUS_ONE = (PRECISION + 1);
	vector_sampler #(
		.N(PRECISION)
	) ff_samp(
		.rst(rst),
		.clk(spkclk),
		.in(psum),
		.out(activation)
	);

endmodule
