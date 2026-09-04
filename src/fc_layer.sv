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
// Date         : Feb 09, 2023
// File         : layer.sv
// Desc         : Fully-connected layer of cuba_lif neurons.
// -----------------------------------------------------------------------------*/

/* -----------------------------------------------------------------------------
Modifications Copyright (c) 2026 Drexel University

// Modified by  : Sarah Johari (sj984@drexel.edu)
// Date         : 2025
// File         : fc_layer.sv
//
// ─── Modifications ──────────────────────────────────────────────
//
//   1. Added WT_INTEGER_PRECISION parameter.
//      Passed through to cuba_lif → bmem_fc for configurable
//      integer bits in weight fixed-point representation.
//
//   2. Added rst_neuron port.
//      Per-image reset that clears LIF state without clearing
//      synaptic weights. Passed through to each cuba_lif instance.
//
//   3. Added local registered copies of neuron config.
//      vth, decay_rate, grow_rate, vrest, reset_mechanism, and
//      refractory_period are registered on memclk before fanning
//      out to all FANOUT cuba_lif instances. Reduces timing pressure
//      on the configuration bus.
//
//   4. Replaced syn_access with syn_access_fc.
//      Uses the modified version with XOR-based change detection
//      (inspk_q2 ^ inspk_q3) and no outspk output.
//
//   5. Removed inspk connection to cuba_lif.
//      LIF operates in activation-only mode — spike presence
//      is no longer passed through the datapath.
//
// ─── Description ────────────────────────────────────────────────
//
//   Fully-connected spiking layer. Contains FANOUT neurons, each
//   implemented as a cuba_lif instance (bmem_fc + LIF).
//
//   Architecture:
//     - syn_access_fc (1 instance): detects spike changes, generates
//       read addresses (countdown FANIN-1 → 0), and rd_en / rst_acc.
//       Shared across all neurons (same input spikes, same sweep).
//     - parameterized_decoder (1 instance): decodes wr_addr to select
//       which neuron's BRAM receives the weight write.
//     - cuba_lif (FANOUT instances): each bundles bmem_fc (BRAM + MAC)
//       with a LIF neuron. All share the same rd_addr, rd_en, rst_acc
//       from syn_access_fc, but each has its own weight memory.
//
//   Data flow:
//     inspk → syn_access_fc → rd_addr/rd_en/rst_acc (shared)
//                                    ↓
//     cuba_lif[0..FANOUT-1]: bmem_fc (serial MAC) → LIF → outspk
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   FANIN                Number of pre-synaptic connections per neuron
//   FANOUT               Number of neurons in the layer
//   INTEGER_PRECISION    Integer bits in state variable fixed-point
//   DECIMAL_PRECISION    Fractional bits
//   WT_INTEGER_PRECISION Integer bits in weight fixed-point
//   ADDR_WIDTH           Total address width for weight writes
//   NEU_ADDR_START       Bit position where neuron index starts in wr_addr
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst                Global reset (clears weights + LIF state)
//   rst_neuron         Per-image reset (clears LIF state only)
//   memclk             Memory clock (weight access, MAC accumulation)
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
//   inspk              Input spikes [FANIN-1:0] from previous layer
//   outspk             Output spikes [FANOUT-1:0] — one per neuron
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps


module fc_layer #(
	//configuration parameters
	parameter FANIN 		    = 32,	//fanin of each neuron of the layer
	parameter FANOUT 		    = 10,	//number of neurons in the layer
	parameter INTEGER_PRECISION	= 3,	//integer precision
	parameter DECIMAL_PRECISION = 4,	//decimal precision
	parameter WT_INTEGER_PRECISION =2, 
	// parameter ADDR_WIDTH_NEURON = 10,	//addr width for neuron
	// parameter ADDR_WIDTH_FANIN 	= 10,	//addr width for fanin	
	parameter ADDR_WIDTH        = 24,
	parameter NEU_ADDR_START = 12,
	//local parameters
	//localparam ADDR_WIDTH 		= (ADDR_WIDTH_NEURON+ADDR_WIDTH_FANIN),		//address width
	localparam FANIN_WIDTH		= $clog2(FANIN),				//log2 of FANIN
	localparam FANOUT_WIDTH		= $clog2(FANOUT),				//log2 of FANOUT
	localparam WT_PRECISION		= (1+WT_INTEGER_PRECISION+DECIMAL_PRECISION),			//bit precision for synaptic weights
	localparam PRECISION 		= (1+INTEGER_PRECISION+DECIMAL_PRECISION)	//bit precision for state variables
)(
	input rst,				//reset
	input rst_neuron,    
	input memclk,				//memory clock
	input spkclk,				//spike clock
	//neuron parameters from configuration registers
	input [PRECISION-1:0] vth,		//neuron threshold voltage
	input [PRECISION-1:0] decay_rate,	//membrane decay rate
	input [PRECISION-1:0] grow_rate,	//membrane grow rate
	input [PRECISION-1:0] vrest,		//neuron resting potential
	input [PRECISION-1:0] reset_mechanism,	//neuron reset mechanism
	input [PRECISION-1:0] refractory_period,//neuron refractory period
	input wr_en,				//write enable to synaptic memory
	input [ADDR_WIDTH-1:0] wr_addr,		//write address to synaptic memory
	input [WT_PRECISION-1:0] wr_data,	//write data (weights) to synaptic memory of precision = WT_PRECISION.
	input [FANIN-1:0] inspk,		//spike input from pre-synaptic connections
	output [FANOUT-1:0] outspk		//spike output from lifs
);


	
	// Per-layer local registered copies of neuron config.
	reg [PRECISION-1:0] vth_local              ;
	reg [PRECISION-1:0] decay_rate_local       ;
	reg [PRECISION-1:0] grow_rate_local        ;
	reg [PRECISION-1:0] vrest_local            ;
	reg [PRECISION-1:0] reset_mechanism_local  ;
	reg [PRECISION-1:0] refractory_period_local;

	
	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			vth_local               <= '0;
			decay_rate_local        <= '0;
			grow_rate_local         <= '0;
			vrest_local             <= '0;
			reset_mechanism_local   <= '0;
			refractory_period_local <= '0;
		end else begin
			vth_local               <= vth;
			decay_rate_local        <= decay_rate;
			grow_rate_local         <= grow_rate;
			vrest_local             <= vrest;
			reset_mechanism_local   <= reset_mechanism;
			refractory_period_local <= refractory_period;
		end
	end


	//instantiate the write address decoder to choose the target neuron
	wire [FANOUT-1:0] wr_addr_decode;	//decoded write address
	parameterized_decoder #(
		.N(FANOUT)
	) wr_addr_decoder(
		.en(wr_en),
		.in(wr_addr[(FANOUT_WIDTH+NEU_ADDR_START-1):NEU_ADDR_START]),
		.out(wr_addr_decode)
	);



	//instantiate the read address decoder
	wire spk_int,rst_acc,rd_en;
	wire [FANIN_WIDTH-1:0] rd_addr;
	syn_access_fc #(
		.FANIN(FANIN)
	) rd_addr_decoder(
		.rst(rst),
		.memclk(memclk),
		.inspk(inspk),
		// .outspk(spk_int),
		.rst_acc(rst_acc),
		.rd_en(rd_en),
		.rd_addr(rd_addr)
	);

	wire [PRECISION-1:0] vmem_int [FANOUT-1:0];	//internal signal to capture vmem output of all LIF neurons

	
	//parametrically instantiate cuba_lif modules 
	genvar i;
	generate
	for (i=0;i<FANOUT;i=i+1) begin : neuron
		cuba_lif #(
			//configuration parameters
			.FANIN(FANIN),					//number of fanin of each neuron in the layer
			.INTEGER_PRECISION(INTEGER_PRECISION),		//integer precision
			.WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
			.DECIMAL_PRECISION(DECIMAL_PRECISION)		//decimal precision
		) cuba_lif_inst(
			.rst(rst),					//reset
			.rst_neuron(rst_neuron),
			.memclk(memclk),				//memory clock
			.spkclk(spkclk),				//spike clock
			//neuron parameters from configuration registers
			.vth(vth_local),
			.decay_rate(decay_rate_local),
			.grow_rate(grow_rate_local),
			.vrest(vrest_local),
			.reset_mechanism(reset_mechanism_local),
			.refractory_period(refractory_period_local),
			.wr_en(wr_addr_decode[i]),			//write enable for writing into the synaptic weights
			.wr_addr(wr_addr[FANIN_WIDTH-1:0]),		//memory address
			.wr_data(wr_data),				//write data
			.rd_en(rd_en),					//read enable
			.rd_addr(rd_addr),				//read address
			.rst_acc(rst_acc),				//reset accumulator
			.outspk(outspk[i]),				//output spike
			.vmem(vmem_int[i])				//output membrane potential for monitoring
		);
	end
	endgenerate
	
endmodule
