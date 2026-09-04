/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Jul 2025
// File         : bmem_cnn.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Combined BRAM weight storage + parallel MAC datapath for one
//   (output_channel, input_channel) pair in the CNN layer.
//   Instantiated OUT_CHANNEL × IN_CHANNEL times in cnn_layer.
//
//   Extends the FC version (bmem_fc) to support 2D convolution:
//     - bmem_fc:  single psum accumulator, FANIN weight entries
//     - bmem_cnn: FANOUT parallel psum accumulators, MEM_SIZE weight entries
//
//   Each psum[i] corresponds to one output spatial position (window).
//   All windows share the same BRAM and rd_data, but each has its
//   own rd_en[i] and rst_acc[i] gating from syn_access_cnn.
//
// ─── Functional Blocks ──────────────────────────────────────────
//
//   1. Block RAM (memclk domain)
//      MEM_SIZE entries (= X_KERNEL × Y_KERNEL) of WT_PRECISION bits.
//      Holds one kernel's worth of synaptic weights.
//      Synchronous write + registered read (1-cycle latency).
//
//   2. Pipeline register: rd_en_q
//      Delays rd_en by 1 cycle to align with BRAM read latency.
//
//   3. Partial-sum accumulators: psum[FANOUT]
//      One per output spatial position.
//      psum[i] cleared by rst_acc[i], updated when rd_en_q[i] is high.
//      All share the same rd_data (one weight read per cycle),
//      but accumulate independently based on per-window spike gating.
//
//   4. Quantized adder: FANOUT instances of qadd
//      Sign-extends rd_data from WT_PRECISION to PRECISION,
//      then adds to psum. Shared weight, parallel accumulation.
//
//   5. Sampling register (multibit_sampler):
//      Samples psum[FANOUT] from memclk onto spkclk domain,
//      producing activation[FANOUT] for the LIF neurons.
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   X_FANIN              Input channel height
//   Y_FANIN              Input channel width
//   X_KERNEL             Convolution kernel height
//   Y_KERNEL             Convolution kernel width
//   STRIDE               Convolution stride
//   INTEGER_PRECISION    Integer bits in state variable fixed-point
//   DECIMAL_PRECISION    Fractional bits
//   WT_INTEGER_PRECISION Integer bits in weight fixed-point
//
//   Derived:
//     FANOUT       = X_FANOUT × Y_FANOUT (output spatial positions)
//     MEM_SIZE     = X_KERNEL × Y_KERNEL (weight entries per BRAM)
//     WT_PRECISION = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION
//     PRECISION    = 1 + INTEGER_PRECISION + DECIMAL_PRECISION
//     ADDR_WIDTH   = clog2(MEM_SIZE)
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst          Async reset (clears psum, rd_en_q)
//   memclk       Memory clock (BRAM access, MAC accumulation)
//   spkclk       Spike clock (CDC target for activation output)
//   wr_en        Weight write enable
//   wr_addr      Weight write address [ADDR_WIDTH-1:0]
//   wr_data      Weight data [WT_PRECISION-1:0]
//   rd_en        Per-window read enable [FANOUT-1:0] (from syn_access_cnn)
//   rd_addr      Kernel read address [ADDR_WIDTH-1:0] (from syn_access_cnn)
//   rst_acc      Per-window accumulator reset [FANOUT-1:0]
//   activation   Output [FANOUT][PRECISION] — accumulated psum
//
// ─── Timing ─────────────────────────────────────────────────────
//
//   Cycle N:   rd_addr selects kernel position k, rd_en[i] active per window
//   Cycle N+1: rd_data available, rd_en_q[i] aligns, psum[i] accumulates
//   After MEM_SIZE cycles: psum[i] holds the convolution result for window i
//   multibit_sampler captures the result onto spkclk for the LIF neuron.
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps


module bmem_cnn #(
	//configurable parameters
	parameter X_FANIN 		    = 4,	
	parameter Y_FANIN 		    = 5,	
	parameter X_KERNEL          = 2, 			
	parameter Y_KERNEL          = 3, 			
	parameter STRIDE            = 2,         
	parameter INTEGER_PRECISION = 3,	
	parameter DECIMAL_PRECISION	= 4,	
	parameter WT_INTEGER_PRECISION = 2,

	//local parameters
	localparam X_FANOUT         =((X_FANIN - X_KERNEL)/ STRIDE) +1,
	localparam Y_FANOUT         = ((Y_FANIN - Y_KERNEL)/ STRIDE) +1,
	localparam FANOUT           = X_FANOUT * Y_FANOUT,
	localparam FANIN 	    	= X_FANIN * Y_FANIN,	
	localparam MEM_SIZE         = X_KERNEL * Y_KERNEL,
	localparam WT_PRECISION     = (1+WT_INTEGER_PRECISION+DECIMAL_PRECISION),			
	localparam PRECISION 	    = (1+INTEGER_PRECISION+DECIMAL_PRECISION),	
	localparam ADDR_WIDTH 	    = $clog2(MEM_SIZE)	
)(
	input rst,		
	input memclk,				
	input spkclk,				
	input wr_en,				
	input [ADDR_WIDTH-1:0] wr_addr,		
	input [WT_PRECISION-1:0] wr_data,	
	input [FANOUT-1:0]rd_en,				
	input [ADDR_WIDTH-1:0] rd_addr,		
	input [FANOUT-1:0]rst_acc,

	output [PRECISION-1:0] activation [FANOUT-1:0]
);

	reg [WT_PRECISION-1:0] rd_data;
	reg [FANOUT-1:0]rd_en_q;

	//instantiate the memory
	(* ram_style = "block" *) reg [WT_PRECISION-1:0] mem [MEM_SIZE-1:0];
	//(* ram_style = "block" *) reg [WT_PRECISION-1:0] mem [KERNEL_SIZE-1:0][FEATURE_MAP-1:0];

	
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
	reg [PRECISION-1:0]psum [FANOUT-1:0] ;
	wire [PRECISION-1:0] psum_int [FANOUT-1:0];

	genvar i;
	generate
		for (i = 0; i < FANOUT; i = i + 1) begin : psum_reg
		always @(posedge memclk or posedge rst) begin
			if (rst) begin
				psum[i] <= 0;
			end
			else begin
				if (rst_acc[i]) begin
					psum[i] <= 0;
				end
				else begin
					if (rd_en_q[i]) begin
						psum[i] <= psum_int[i];
					end
				end
			end
		end
		end
		endgenerate

	//quantized adder
	localparam INT_PRECISION = PRECISION - WT_PRECISION;

	genvar j;
	generate
	for (j=0;j<FANOUT;j=j+1) begin
		qadd #(
			.N(PRECISION)
		) psum_inst(
			.a(psum[j]),
			.b({ {INT_PRECISION{rd_data[WT_PRECISION-1]}},rd_data }),
			.q_result(psum_int[j])
		);
	end
	endgenerate


	localparam PRECISION_IS = FANOUT;
	
	// assign activation = psum;
	multibit_sampler#(
		.N(PRECISION),
		.M(FANOUT)
	) ff_samp(
		.rst(rst),
		.clk(spkclk),
		.in(psum),
		.out(activation)
	);
endmodule
