/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2023-2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Sep 2, 2025
// File         : scnncore.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   Top-level spiking CNN accelerator core.
//   Implements a 4-layer feed-forward SNN:
//     CNN layer 0 → CNN layer 1 → flatten → FC layer 0 → FC layer 1
//
//   Supports weight/bias programming via a shared write bus
//   and neuron parameter configuration via registers.
//
// ─── Architecture ───────────────────────────────────────────────
//
//   ┌────────────┐    ┌────────────┐    ┌──────────┐    ┌──────────┐
//   │ CNN layer 0│───→│ CNN layer 1│───→│ FC layer0│───→│ FC layer1│───→ spk_out
//   │ (conv+LIF) │    │ (conv+LIF) │    │ (288→64) │    │ (64→3)   │
//   └────────────┘    └────────────┘    └──────────┘    └──────────┘
//         ↑                  ↑                ↑               ↑
//       spk_in         spk_int_0        spk_out_flat     spk_int_fc0
//
//   Between CNN layer 1 and FC layer 0, the multi-channel 2D output
//   is flattened into a 1D spike vector (OUT_CH_L1 × FANOUT_L1).
//
// ─── Sub-modules ────────────────────────────────────────────────
//
//   cnn_layer            [2]   Spiking convolutional layers
//   fc_layer             [2]   Fully-connected spiking layers
//   parameterized_decoder[2]   Layer-select decoders (weight + bias writes)
//   decoder_neuron_config[1]   Neuron parameter config registers
//
// ─── Programming Interface ──────────────────────────────────────
//
//   Three write modes controlled by mem_write, cfg_write, bias_write:
//
//     mem_write=1:  Write synaptic weights.
//       wr_addr[LAYER_ADDR_START+:LAYER_WIDTH] selects the layer.
//       Remaining wr_addr bits select the BRAM within that layer.
//       wr_data[WT_PRECISION-1:0] is the weight value.
//
//     bias_write=1: Write bias values.
//       Same layer select as mem_write.
//       wr_addr[OUT_CH_ADDR_START+:OUT_CH_WIDTH] selects output channel.
//       wr_data[PRECISION-1:0] is the bias value.
//
//     cfg_write=1:  Write neuron configuration registers.
//       decoder_neuron_config maps wr_addr to one of 6 registers:
//       vth, decay_rate, grow_rate, vrest, reset_mechanism,
//       refractory_period. Shared across all layers.
//
// ─── Reset Strategy ─────────────────────────────────────────────
//
//   rst:         Global reset — clears all weights, neuron state,
//                and config registers. Per-layer replicated copies
//                (rst_layer0, rst_layer1, rst_fc0, rst_fc1) with
//                max_fanout=50000 constraint to ease timing.
//
//   rst_neuron:  Per-image reset — clears LIF state only (vmem,
//                refr_cnt, outspk). Weights and biases preserved.
//                Also replicated per layer with max_fanout constraint.
//
// ─── CNN Layer Configuration ────────────────────────────────────
//
//   Layer geometry comes from cnn_config.svh (included as parameters):
//     cnn_config[layer][0..6] = {x_kernel, y_kernel, stride,
//                                 in_channel, out_channel,
//                                 x_fanout, y_fanout}
//
//   Layer 0: spk_in → cnn_layer → spk_int_0
//     Input:  X_FANIN × Y_FANIN, IN_CHANNEL channels
//     Output: cnn_config[0][5] × cnn_config[0][6], OUT_CH_0 channels
//
//   Layer 1: spk_int_0 → cnn_layer → spk_int_1
//     Input:  cnn_config[0][5] × cnn_config[0][6], OUT_CH_0 channels
//     Output: cnn_config[1][5] × cnn_config[1][6], OUT_CH_1 channels
//
// ─── FC Layer Configuration ─────────────────────────────────────
//
//   FC layer 0: FANIN_FC0 = OUT_CH_L1 × FANOUT_L1, FANOUT_FC0 = 64
//   FC layer 1: FANIN = 64, FANOUT = 3 (output neurons)
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   System-wide parameters from parameters.vh (precision, address
//   encoding, clock timing, network dimensions).
//   Per-layer CNN config from cnn_config.svh.
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   mem_write      Weight write enable
//   cfg_write      Config register write enable
//   bias_write     Bias write enable
//   wr_addr        Shared write address [ADDR_WIDTH-1:0]
//   wr_data        Shared write data [DATA_WIDTH-1:0]
//   rst            Global reset
//   rst_neuron     Per-image neuron reset
//   memclk         Memory clock (BRAM access, MAC accumulation)
//   spkclk         Spike clock (LIF neuron updates)
//   spk_in         Input spikes [IN_CHANNEL][FANIN]
//   spk_out        Output spikes [FANOUT-1:0] (final layer)
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps
`include "cnn_config.svh"
`include "parameters.svh"

module scnncore #(
	localparam IN_CHANNEL = cnn_config[0][3],
	localparam OUT_CH_L0   = cnn_config[0][4],
	localparam FANOUT_L0 = cnn_config[0][5]*cnn_config[0][6],
	localparam OUT_CHANNEL = cnn_config[HIDDEN_LAYERS-2][4]
	)(
	//IOs for loading layer-by-layer synaptic weights into the memory and programming the configuration registers.
	//mem_write = 0, reg_write = 1 ==> write to configuration registers
	//mem_write = 1, reg_write = 0 ==> write to synaptic memory
	input mem_write,			        	//write enable for synaptic memory
	input cfg_write,				        //write enable for configuration registers
	input [ADDR_WIDTH-1:0] wr_addr,			//memory/configuration address
	input [DATA_WIDTH-1:0] wr_data,			//memory/configuration data 
	input bias_write,				        // write enable for bias registers
	//IOs for data processing
	input rst,					//reset signal 
	input rst_neuron,
	input memclk,					//memory clock
	input spkclk,					//spike clock
	input [FANIN-1:0] spk_in [IN_CHANNEL-1:0],		//spike input to the input layer
	output [FANOUT-1:0] spk_out
	);


	// Per-layer reset replication.
	reg rst_cfg;
	reg rst_layer0;
	reg rst_layer1;
	reg rst_fc0;
	reg rst_fc1;

	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			rst_cfg    <= 1'b1;
			rst_layer0 <= 1'b1;
			rst_layer1 <= 1'b1;
			rst_fc0    <= 1'b1;
			rst_fc1    <= 1'b1;
		end else begin
			rst_cfg    <= 1'b0;
			rst_layer0 <= 1'b0;
			rst_layer1 <= 1'b0;
			rst_fc0    <= 1'b0;
			rst_fc1    <= 1'b0;
		end
	end

	// Per-layer reset replication.
	reg rst_neuron_layer0;
	reg rst_neuron_layer1;
	reg rst_neuron_fc0;
	reg rst_neuron_fc1;

	always @(posedge memclk or posedge rst_neuron) begin
		if (rst_neuron) begin
			rst_neuron_layer0 <= 1'b1;
			rst_neuron_layer1 <= 1'b1;
			rst_neuron_fc0    <= 1'b1;
			rst_neuron_fc1    <= 1'b1;
		end else begin
			rst_neuron_layer0 <= 1'b0;
			rst_neuron_layer1 <= 1'b0;
			rst_neuron_fc0    <= 1'b0;
			rst_neuron_fc1    <= 1'b0;
		end
	end


	// ── Layer select decoder for weight writes
	wire [HARDWARE_LAYERS-1:0] wr_addr_en;
	parameterized_decoder #(
		.N(HARDWARE_LAYERS)
	) wr_addr_decoder(
		.en(mem_write),
		.in(wr_addr[LAYER_WIDTH+LAYER_ADDR_START-1:LAYER_ADDR_START]),
		.out(wr_addr_en)
	);

	// Layer select decoder for bias writes ────────────────
	// Uses same layer address field as weight writes.
	// Only CNN layers (0, 1, 2) get bias; FC layer does not.
	wire [HARDWARE_LAYERS-1:0] bias_addr_en;
	parameterized_decoder #(
		.N(HARDWARE_LAYERS)
	) bias_addr_decoder(
		.en(bias_write),
		.in(wr_addr[LAYER_WIDTH+LAYER_ADDR_START-1:LAYER_ADDR_START]),
		.out(bias_addr_en)
	);

	//instantiate the cfg decoder for neuron parameters
	wire [PRECISION-1:0] vth;
	wire [PRECISION-1:0] decay_rate;
	wire [PRECISION-1:0] grow_rate;
	wire [PRECISION-1:0] vrest;
	wire [PRECISION-1:0] reset_mechanism;
	wire [PRECISION-1:0] refractory_period;
	// wire [DATA_WIDTH-1:0] layer_to_monitor;
	// wire [DATA_WIDTH-1:0] neuron_to_monitor;
	decoder_neuron_config #(
		.ADDR_WIDTH(ADDR_WIDTH),
		.DATA_WIDTH(DATA_WIDTH),
		.NEURON_CFG_REG(NEURON_CFG_REG),
		.PRECISION(PRECISION)
	) cfg_neuron_decoder(
		.rst(rst_cfg),
		.clk(memclk),
		.wr_en(cfg_write),
		.wr_addr(wr_addr),
		.wr_data(wr_data),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period)
	);


	// ═══════════════════════════════════════════════════════════════
	// CNN Layer 0
	// ═══════════════════════════════════════════════════════════════
	wire [FANOUT_L0-1:0] spk_int_0 [OUT_CH_L0-1:0];   
	wire [PRECISION-1:0] vmem_int_0 [OUT_CH_L0-1:0][FANOUT_L0-1:0];	      

	cnn_layer #(
		.X_FANIN(X_FANIN),
		.Y_FANIN(Y_FANIN),
		.X_KERNEL(cnn_config[0][0]),
		.Y_KERNEL(cnn_config[0][1]),
		.STRIDE(cnn_config[0][2]),
		.IN_CHANNEL(cnn_config[0][3]),
		.OUT_CHANNEL(cnn_config[0][4]),
		.IN_CH_ADDR_START(IN_CH_ADDR_START),
		.OUT_CH_ADDR_START(OUT_CH_ADDR_START),
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION),
		.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
		.ADDR_WIDTH(LAYER_ADDR_START)
	) layer_0(
		.rst(rst_layer0),
		.rst_neuron(rst_neuron_layer0),
		.memclk(memclk),
		.spkclk(spkclk),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period),
		.wr_en(wr_addr_en[0]),
		.wr_addr(wr_addr[LAYER_ADDR_START-1:0]),
		.wr_data(wr_data[WT_PRECISION-1:0]),
		.bias_wr_en(bias_addr_en[0]),
		.bias_wr_addr(wr_addr[$clog2(cnn_config[0][4])-1 + OUT_CH_ADDR_START:OUT_CH_ADDR_START]),
		.bias_wr_data(wr_data[PRECISION-1:0]),
		.inspk(spk_in),
		.outspk(spk_int_0)
	);


	// ═══════════════════════════════════════════════════════════════
	// CNN Layer 1
	// ═══════════════════════════════════════════════════════════════
	localparam FANOUT_FM_L1 = cnn_config[1][5]*cnn_config[1][6];
	localparam OUT_CH_L1    = cnn_config[1][4];
	wire [FANOUT_FM_L1-1:0] spk_int_1 [OUT_CH_L1-1:0];   	
	cnn_layer #(
		.X_FANIN(cnn_config[0][5]),
		.Y_FANIN(cnn_config[0][6]),
		.X_KERNEL(cnn_config[1][0]),
		.Y_KERNEL(cnn_config[1][1]),
		.STRIDE(cnn_config[1][2]),
		.IN_CHANNEL(cnn_config[1][3]),
		.OUT_CHANNEL(cnn_config[1][4]),
		.IN_CH_ADDR_START(IN_CH_ADDR_START),
		.OUT_CH_ADDR_START(OUT_CH_ADDR_START),
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION),
		.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
		.ADDR_WIDTH(LAYER_ADDR_START)
	)layer_1(
		.rst(rst_layer1),
		.rst_neuron(rst_neuron_layer1),
		.memclk(memclk),
		.spkclk(spkclk),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period),
		.wr_en(wr_addr_en[1]),
		.wr_addr(wr_addr[LAYER_ADDR_START-1:0]),
		.wr_data(wr_data[WT_PRECISION-1:0] ),
		.bias_wr_en(bias_addr_en[1]),
		.bias_wr_addr(wr_addr[$clog2(cnn_config[1][4])-1 + OUT_CH_ADDR_START:OUT_CH_ADDR_START]),
		.bias_wr_data(wr_data[PRECISION-1:0]),
		.inspk(spk_int_0),
		.outspk(spk_int_1)
	);

       
	// ═══════════════════════════════════════════════════════════════
	// Flatten CNN Layer 1 output → FC input
	// 32 channels × 9 positions = 288 bits
	// ═══════════════════════════════════════════════════════════════
	logic [FANOUT_FM_L1*OUT_CH_L1-1:0] spk_out_flat;
	always @(*) begin
		for (int j = 0; j < OUT_CH_L1; j++) begin
			spk_out_flat[(j+1)*FANOUT_FM_L1-1 -: FANOUT_FM_L1] = spk_int_1[j];
		end
	end



	// ═══════════════════════════════════════════════════════════════
	// FC Layer 0 (hidden):  Linear(288→64, bias=False)
	// ═══════════════════════════════════════════════════════════════
	localparam FANIN_FC0  = OUT_CH_L1 * FANOUT_FM_L1;  // 32×9 = 288
	localparam FANOUT_FC0 = 64;
 
	wire [FANOUT_FC0-1:0] spk_int_fc0;
 
	fc_layer #(
		.FANIN(FANIN_FC0),
		.FANOUT(FANOUT_FC0),
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION),
		.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
		.ADDR_WIDTH(LAYER_ADDR_START),
		.NEU_ADDR_START(FANIN_ENC_BITS)
	) layer_fc0(
		.rst(rst_fc0),
		.rst_neuron(rst_neuron_fc0),
		.memclk(memclk),
		.spkclk(spkclk),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period),
		.wr_en(wr_addr_en[2]),
		.wr_addr(wr_addr[LAYER_ADDR_START-1:0]),
		.wr_data(wr_data[WT_PRECISION-1:0]),
		.inspk(spk_out_flat),
		.outspk(spk_int_fc0)
	);
 
 
	// ═══════════════════════════════════════════════════════════════
	// FC Layer 1 (output):  Linear(64→3, bias=False)
	// ═══════════════════════════════════════════════════════════════
	fc_layer #(
		.FANIN(FANOUT_FC0),
		.FANOUT(FANOUT),
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION),
		.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
		.ADDR_WIDTH(LAYER_ADDR_START),
		.NEU_ADDR_START(FANIN_ENC_BITS)
	) layer_fc1(
		.rst(rst_fc1),
		.rst_neuron(rst_neuron_fc1),
		.memclk(memclk),
		.spkclk(spkclk),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period),
		.wr_en(wr_addr_en[3]),
		.wr_addr(wr_addr[LAYER_ADDR_START-1:0]),
		.wr_data(wr_data[WT_PRECISION-1:0]),
		.inspk(spk_int_fc0),
		.outspk(spk_out)
	);


endmodule
