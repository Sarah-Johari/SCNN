/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Jul 07, 2025 (modularized May 2026)
// File         : cnn_layer.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Spiking convolutional layer — fully unrolled architecture.
//   All output channels are computed in parallel. Every
//   (output_channel, input_channel) pair has its own bmem_cnn
//   instance with dedicated BRAM and MAC datapath.
//
// ─── Sub-modules ────────────────────────────────────────────────
//
//   syn_access_cnn   [IN_CHANNEL]                 Read address sequencer
//   bmem_cnn         [OUT_CHANNEL × IN_CHANNEL]   BRAM + MAC datapath
//   bram_decoder     [1]                           Weight write decoder
//   bias_store_gated [1]                           Bias register + spike gating
//   xchan_bias_acc   [1]                           Cross-channel acc + bias
//   lif              [OUT_CHANNEL × FANOUT]        LIF neurons
//
// ─── Data Flow ──────────────────────────────────────────────────
//
//   inspk[IN_CHANNEL]
//     ↓
//   syn_access_cnn (per input channel)
//     → rd_addr, rd_en, rst_acc (shared across all output channels)
//     ↓
//   bmem_cnn [OUT_CHANNEL × IN_CHANNEL]
//     → int_activation [OUT_CHANNEL][IN_CHANNEL][FANOUT]
//     ↓
//   xchan_bias_acc 
//     → sum across IN_CHANNEL + bias_gated
//     → activation_post_bias [OUT_CHANNEL][FANOUT]
//     ↓
//   lif [OUT_CHANNEL × FANOUT]
//     → outspk, vmem
//
// ─── Neuron Config Registers ────────────────────────────────────
//
//   vth, decay_rate, grow_rate, vrest, reset_mechanism,
//   refractory_period are registered on memclk with per-output-channel
//   copies. Reduces fanout and eases timing from the config bus.
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   X_FANIN              Input feature map height
//   Y_FANIN              Input feature map width
//   X_KERNEL             Convolution kernel height
//   Y_KERNEL             Convolution kernel width
//   STRIDE               Convolution stride
//   IN_CHANNEL           Number of input channels
//   OUT_CHANNEL          Number of output channels
//   IN_CH_ADDR_START     Bit position of input channel index in wr_addr
//   OUT_CH_ADDR_START    Bit position of output channel index in wr_addr
//   INTEGER_PRECISION    Integer bits in state variable fixed-point
//   DECIMAL_PRECISION    Fractional bits
//   WT_INTEGER_PRECISION Integer bits in weight fixed-point
//   ADDR_WIDTH           Total write address width
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst                Global reset (clears weights + neuron state)
//   rst_neuron         Per-image reset (clears neuron state only)
//   memclk             Memory clock (BRAM access, MAC accumulation)
//   spkclk             Spike clock (LIF neuron updates)
//   vth                Threshold voltage [PRECISION-1:0]
//   decay_rate         Membrane decay rate [PRECISION-1:0]
//   grow_rate          Activation growth rate [PRECISION-1:0]
//   vrest              Resting potential [PRECISION-1:0]
//   reset_mechanism    Reset mode selector [PRECISION-1:0]
//   refractory_period  Refractory counter load value [PRECISION-1:0]
//   wr_en              Weight write enable
//   wr_addr            Weight write address [ADDR_WIDTH-1:0]
//   wr_data            Weight data [WT_PRECISION-1:0]
//   bias_wr_en         Bias write enable
//   bias_wr_addr       Output channel index for bias write [OUT_CH_WIDTH-1:0]
//   bias_wr_data       Bias value [PRECISION-1:0]
//   inspk              Input spikes [IN_CHANNEL][FANIN]
//   outspk             Output spikes [OUT_CHANNEL][FANOUT]
//   activation         Debug: post-bias activation [OUT_CHANNEL][FANOUT]
//   act                Debug: single activation tap
//   vmem               Membrane voltage [OUT_CHANNEL][FANOUT]
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module cnn_layer #(
	//configuration parameters
	parameter X_FANIN 		    = 4,	
	parameter Y_FANIN 		    = 5,	
	parameter X_KERNEL          = 2, 			
	parameter Y_KERNEL          = 3, 			
	parameter STRIDE            = 1,       
	parameter IN_CHANNEL        = 1,
	parameter OUT_CHANNEL       = 1,
	parameter IN_CH_ADDR_START  = 1,
	parameter OUT_CH_ADDR_START = 1,
	parameter FANIN_ENC_BITS    =12,
	parameter INTEGER_PRECISION	= 7,	
	parameter DECIMAL_PRECISION = 8,	
	parameter WT_INTEGER_PRECISION =2, 
	parameter ADDR_WIDTH 	    = 32,


	localparam MEM_SIZE         = X_KERNEL * Y_KERNEL,
	localparam ADDR_WIDTH_MEM   = $clog2(MEM_SIZE),
	localparam X_FANOUT         =((X_FANIN - X_KERNEL)/ STRIDE) +1,
	localparam Y_FANOUT         = ((Y_FANIN - Y_KERNEL)/ STRIDE) +1,
	localparam FANOUT           = X_FANOUT * Y_FANOUT,
	localparam FANIN 	    	= X_FANIN * Y_FANIN,	
	localparam IN_CH_WIDTH      = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL),      
    localparam OUT_CH_WIDTH     = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL),		
	localparam WT_PRECISION		= (1+WT_INTEGER_PRECISION+DECIMAL_PRECISION),			
	localparam PRECISION 		= (1+INTEGER_PRECISION+DECIMAL_PRECISION)	
)(
	input rst,			
	input rst_neuron,
	input memclk,			
	input spkclk,			
	input [PRECISION-1:0] vth,		
	input [PRECISION-1:0] decay_rate,	
	input [PRECISION-1:0] grow_rate,
	input [PRECISION-1:0] vrest,		
	input [PRECISION-1:0] reset_mechanism,	
	input [PRECISION-1:0] refractory_period,
	input wr_en,			
	input [ADDR_WIDTH-1:0] wr_addr,		
	input [WT_PRECISION-1:0] wr_data,	
	input bias_wr_en,                            
	input [OUT_CH_WIDTH-1:0] bias_wr_addr, 
	input [PRECISION-1:0] bias_wr_data,           
	input [FANIN-1:0] inspk [IN_CHANNEL-1:0],		
	output [FANOUT-1:0] outspk [OUT_CHANNEL-1:0]	
);



	// Per-output-channel local registered copies of neuron config.
	reg [PRECISION-1:0] vth_local              [OUT_CHANNEL-1:0];
	reg [PRECISION-1:0] decay_rate_local       [OUT_CHANNEL-1:0];
	reg [PRECISION-1:0] grow_rate_local        [OUT_CHANNEL-1:0];
	reg [PRECISION-1:0] vrest_local            [OUT_CHANNEL-1:0];
	reg [PRECISION-1:0] reset_mechanism_local  [OUT_CHANNEL-1:0];
	reg [PRECISION-1:0] refractory_period_local[OUT_CHANNEL-1:0];

	genvar cfg_i;
	generate
		for (cfg_i = 0; cfg_i < OUT_CHANNEL; cfg_i = cfg_i + 1) begin : cfg_local_regs
			always @(posedge memclk or posedge rst) begin
				if (rst) begin
					vth_local[cfg_i]               <= '0;
					decay_rate_local[cfg_i]        <= '0;
					grow_rate_local[cfg_i]         <= '0;
					vrest_local[cfg_i]             <= '0;
					reset_mechanism_local[cfg_i]   <= '0;
					refractory_period_local[cfg_i] <= '0;
				end else begin
					vth_local[cfg_i]               <= vth;
					decay_rate_local[cfg_i]        <= decay_rate;
					grow_rate_local[cfg_i]         <= grow_rate;
					vrest_local[cfg_i]             <= vrest;
					reset_mechanism_local[cfg_i]   <= reset_mechanism;
					refractory_period_local[cfg_i] <= refractory_period;
				end
			end
		end
	endgenerate



	// ─────────────────────────────────────────────────────────────
    // Bias storage + gating
    // ─────────────────────────────────────────────────────────────
    wire [PRECISION-1:0] bias_gated [OUT_CHANNEL-1:0];
 
    bias_store_gated #(
        .OUT_CHANNEL(OUT_CHANNEL),
        .IN_CHANNEL(IN_CHANNEL),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN)
    ) bias_inst (
        .rst(rst),
        .rst_neuron(rst_neuron),
        .memclk(memclk),
        .spkclk(spkclk),
        .bias_wr_en(bias_wr_en),
        .bias_wr_addr(bias_wr_addr),
        .bias_wr_data(bias_wr_data),
        .inspk(inspk),
        .bias_gated(bias_gated)
    );


	// ─────────────────────────────────────────────────────────────
    // BRAM write decoder
    // ─────────────────────────────────────────────────────────────
	wire [OUT_CHANNEL-1:0][IN_CHANNEL-1:0] wr_addr_decode;	
	bram_decoder #(
		.IN_CHANNEL(IN_CHANNEL),
		.OUT_CHANNEL(OUT_CHANNEL)
	) wr_addr_decoder(
		.en (wr_en),
		.in_ch (wr_addr[IN_CH_ADDR_START  +: IN_CH_WIDTH]),
    	.out_ch (wr_addr[OUT_CH_ADDR_START +: OUT_CH_WIDTH]),
		.bram_sel (wr_addr_decode)
	);


	// ─────────────────────────────────────────────────────────────
    // syn_access_cnn — IN_CHANNEL instances
    // ─────────────────────────────────────────────────────────────
	reg [FANOUT-1:0] rd_en   [IN_CHANNEL-1:0];
	reg [FANOUT-1:0] rst_acc [IN_CHANNEL-1:0]; 
	// reg [FANOUT-1:0] spk_int [IN_CHANNEL-1:0];
	reg [ADDR_WIDTH_MEM-1:0] rd_addr [IN_CHANNEL-1:0];

	genvar i;
	generate 
		for (i=0; i < IN_CHANNEL; i++) begin
			syn_access_cnn #(
				.X_FANIN(X_FANIN),
				.Y_FANIN(Y_FANIN),
				.X_KERNEL(X_KERNEL),
				.Y_KERNEL(Y_KERNEL),
				.STRIDE(STRIDE)
			) rd_addr_decoder(
				.rst(rst),
				.memclk(memclk),
				.inspk(inspk[i]),
				// .outspk(spk_int[i]),
				.rst_acc(rst_acc[i]),
				.rd_en(rd_en[i]),
				.rd_addr(rd_addr[i])
			);
		end
	endgenerate

	// ─────────────────────────────────────────────────────────────
    // bmem_cnn — OUT_CHANNEL × IN_CHANNEL (BRAM + MAC)
    // ─────────────────────────────────────────────────────────────
	//wire [FANOUT-1:0] int_spk [OUT_CHANNEL-1:0][IN_CHANNEL-1:0];
	wire [PRECISION-1:0] int_activation [OUT_CHANNEL-1:0][IN_CHANNEL-1:0][FANOUT-1:0];
	
	genvar j;
	genvar k;
	generate 
		for (j=0; j < OUT_CHANNEL ; j++) begin
			for (k=0; k < IN_CHANNEL ; k++) begin
				bmem_cnn #(
					.X_FANIN(X_FANIN),
					.Y_FANIN(Y_FANIN),
					.X_KERNEL(X_KERNEL),
					.Y_KERNEL(Y_KERNEL),
					.STRIDE(STRIDE),
					.INTEGER_PRECISION(INTEGER_PRECISION),
					.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
					.DECIMAL_PRECISION(DECIMAL_PRECISION)
				) bmem_cnn_dut(
					.rst(rst),
					.memclk(memclk),
					.spkclk(spkclk),
					.wr_en(wr_addr_decode[j][k]),
					.wr_addr(wr_addr[ADDR_WIDTH_MEM-1:0]),
					.wr_data(wr_data),
					.rd_en(rd_en[k]),
					.rd_addr(rd_addr[k]),
					.rst_acc(rst_acc[k]),
					.activation(int_activation[j][k])
				);
			end
		end 
	endgenerate 


	// ─────────────────────────────────────────────────────────────
    // Cross-channel accumulation + bias (P=OUT_CHANNEL, fully unrolled)
    // ─────────────────────────────────────────────────────────────
    wire [PRECISION-1:0] activation_post_bias [OUT_CHANNEL-1:0][FANOUT-1:0];
 
    xchan_bias_acc #(
		.OUT_CHANNEL(OUT_CHANNEL),
        .IN_CHANNEL(IN_CHANNEL),
        .FANOUT(FANOUT),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) xchan_acc_inst (
        .mac_activation(int_activation),
        .active_bias(bias_gated),
        .xchan_biased(activation_post_bias)
    );


	// ─────────────────────────────────────────────────────────────
    // LIF neurons — OUT_CHANNEL × FANOUT
    // ─────────────────────────────────────────────────────────────
	// logic [PRECISION-1:0] vmem	[OUT_CHANNEL-1:0][FANOUT-1:0];
	genvar q, s;
	generate
	for (q=0 ; q < OUT_CHANNEL ; q=q+1) begin 
		for (s=0 ; s < FANOUT ; s=s+1) begin 
			lif #(
				.INTEGER_PRECISION(INTEGER_PRECISION),		//integer precision
				.DECIMAL_PRECISION(DECIMAL_PRECISION)		//decimal precision
			) lif_inst(
				.rst(rst | rst_neuron),					
				.clk(spkclk),				
				//neuron parameters from configuration registers
				.vth(vth_local[q]),
				.decay_rate(decay_rate_local[q]),
				.grow_rate(grow_rate_local[q]),
				.vrest(vrest_local[q]),
				.reset_mechanism(reset_mechanism_local[q]),
				.refractory_period(refractory_period_local[q]),			
				.activation(activation_post_bias[q][s]),
				.outspk(outspk[q][s]),			
				.vmem()	
			);
		end
	end
	endgenerate

endmodule
