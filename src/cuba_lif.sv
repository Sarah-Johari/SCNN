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
// File         : cuba_lif.v
// Desc         : This is an implementation of a single lif neuron with its
//                pre-synaptic weights. The module instantiates bmem, which is
//                a memory array of FANIN * PRECISION bits. Essentially, these
//                are synaptic weights of each pre-synaptic connections to the
//                LIF neuron. The top module also instantiates the lif module,
//                which is the main code for a leaky integrate-and-fire neuron.
//                The weights from the memory (bmem) are input to the LIF.
// -----------------------------------------------------------------------------*/

/* -----------------------------------------------------------------------------
Modifications Copyright (c) 2026 Drexel University

// Modified by  : Sarah Johari (sj984@drexel.edu)
// Date         : May 2026
//
// ─── Modifications ──────────────────────────────────────────────
//
//   1. Added WT_INTEGER_PRECISION parameter.
//      Original: WT_PRECISION = 1 + DECIMAL_PRECISION (sign + fraction only).
//      Modified: WT_PRECISION = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION
//      (configurable integer bits in weights, passed to bmem).
//
//   2. Added rst_neuron port.
//      New per-image reset that clears LIF state (vmem, refr_cnt, outspk)
//      without clearing bmem weights. LIF receives rst = rst | rst_neuron.
//      Allows re-running inference without re-loading weights.
//
//   3. Removed inspk port and int_spk wire.
//      Original: inspk fed to bmem, bmem produced int_spk (CDC-crossed
//      spike presence), int_spk fed to LIF's inspk input.
//      Modified: neither bmem nor LIF use inspk. Activation is the sole
//      driver of neuron dynamics (activation-only mode).
//
//   4. Removed inspk and outspk connections from bmem instantiation.
//      bmem now only produces activation — no spike passthrough.
//
// ─── Description ────────────────────────────────────────────────
//
//   Single FC neuron: bundles synaptic weight memory (bmem) with a
//   LIF neuron. Used in fc_layer for fully-connected layers.
//
//   Data flow:
//     wr interface → bmem (weight storage + serial MAC on memclk)
//                      ↓
//                  activation (CDC to spkclk inside bmem)
//                      ↓
//                    lif (membrane dynamics on spkclk)
//                      ↓
//                  outspk, vmem
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   FANIN                Number of pre-synaptic connections
//   INTEGER_PRECISION    Integer bits in state variable fixed-point
//   WT_INTEGER_PRECISION Integer bits in weight fixed-point
//   DECIMAL_PRECISION    Fractional bits (shared by weights and state)
//
//   Derived:
//     WT_PRECISION = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION
//     PRECISION    = 1 + INTEGER_PRECISION + DECIMAL_PRECISION
//     ADDR_WIDTH   = clog2(FANIN)
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst                Global reset (clears bmem + LIF)
//   rst_neuron         Per-image reset (clears LIF only, weights kept)
//   memclk             Memory clock (bmem write/read, MAC accumulation)
//   spkclk             Spike clock (LIF neuron update)
//
//   vth                Threshold voltage [PRECISION-1:0]
//   decay_rate         Membrane decay rate [PRECISION-1:0]
//   grow_rate          Activation growth rate [PRECISION-1:0]
//   vrest              Resting potential [PRECISION-1:0]
//   reset_mechanism    Reset mode selector [PRECISION-1:0]
//   refractory_period  Refractory counter load value [PRECISION-1:0]
//
//   wr_en              Weight write enable
//   wr_addr            Weight write address [ADDR_WIDTH-1:0]
//   wr_data            Weight write data [WT_PRECISION-1:0]
//   rd_en              Weight read enable (MAC trigger)
//   rd_addr            Weight read address [ADDR_WIDTH-1:0]
//   rst_acc            Accumulator clear
//
//   outspk             Output spike (1-bit)
//   vmem               Membrane voltage [PRECISION-1:0]
//
// ─── Reset Behavior ─────────────────────────────────────────────
//
//   rst:         Clears everything — bmem weights, LIF state.
//                Must re-program weights after this reset.
//   rst_neuron:  Clears LIF state only (vmem, refr_cnt, outspk).
//                Weights in bmem are preserved. Used between
//                inference runs on different input samples.
//
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module cuba_lif #(
	//configurable parameters
	parameter FANIN 		= 256,			//fanin
	parameter INTEGER_PRECISION	= 3,			//integer precision
	parameter WT_INTEGER_PRECISION =2,
	parameter DECIMAL_PRECISION 	= 4,			//fraction precision
	//local parameters
	localparam WT_PRECISION 	= (1+WT_INTEGER_PRECISION+DECIMAL_PRECISION),			//precision for synaptic weights
	localparam PRECISION 		= (1+INTEGER_PRECISION+DECIMAL_PRECISION),	//precision for state variables
	localparam ADDR_WIDTH		= $clog2(FANIN)		//address width for the memory addresses of fanin of each neuron. 
)(
	input rst,				// global/system reset — resets everything including bmem
	input rst_neuron,         // per-image reset — only resets LIF state
	input memclk,				//memory clock
	input spkclk,				//spike clock
	//neuron parameters from congiguration registers
	input [PRECISION-1:0] vth,		//neuron threshold voltage
	input [PRECISION-1:0] decay_rate,	//membrane decay rate
	input [PRECISION-1:0] grow_rate,	//membrane grow rate
	input [PRECISION-1:0] vrest,		//neuron resting potential
	input [PRECISION-1:0] reset_mechanism,	//neuron reset mechanism
	input [PRECISION-1:0] refractory_period,//neuron refractory period
	//memory write
	input wr_en,				//write enable to synaptic memory
	input [ADDR_WIDTH-1:0] wr_addr,		//write address to synaptic memory
	input [WT_PRECISION-1:0] wr_data,	//write data (weights) to synaptic memory
	//memory read
	input rd_en,				//read enable for synaptic memory
	input [ADDR_WIDTH-1:0] rd_addr,		//read address for synaptic memory
	//accumulator clear
	input rst_acc,	
	//output
	output outspk,				//spike output from lif
	output [PRECISION-1:0] vmem		//membrane potential of the lif 		
);

	// wire int_spk;
	wire [PRECISION-1:0] int_activation;

	//instantiate the bmem
	bmem_fc #(
		.FANIN(FANIN),
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION)
	) bmem_dut(
		.rst(rst),
		.memclk(memclk),
		.spkclk(spkclk),
		.wr_en(wr_en),
		.wr_addr(wr_addr),
		.wr_data(wr_data),
		.rd_en(rd_en),
		.rd_addr(rd_addr),
		.rst_acc(rst_acc),
		.activation(int_activation)
	);
	//instantiate the neuron
	lif #(
		.INTEGER_PRECISION(INTEGER_PRECISION),
		.DECIMAL_PRECISION(DECIMAL_PRECISION)
	) lif_dut(
		.rst(rst | rst_neuron),
		.clk(spkclk),
		.vth(vth),
		.decay_rate(decay_rate),
		.grow_rate(grow_rate),
		.vrest(vrest),
		.reset_mechanism(reset_mechanism),
		.refractory_period(refractory_period),
		.activation(int_activation),
		.outspk(outspk),
		.vmem(vmem)
	);


endmodule
