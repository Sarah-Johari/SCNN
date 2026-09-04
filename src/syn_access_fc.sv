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
// File         : syn_access.v
// Desc         : This is an implementation of address generation for accessing
//                synaptic weights from bmem. It generates a trigger pulse
//                whenever there is a change in spike input. Using this trigger,
//                the accumulator is reset (implemented inside bmem). This module
//                also generates the address for synaptic memory. The module is
//                instantiated inside a layer.
// -----------------------------------------------------------------------------*/

/* -----------------------------------------------------------------------------
Modifications Copyright (c) 2026 Drexel University

// Modified by  : Sarah Johari (sj984@drexel.edu)
// Date         : 2025
// File         : syn_access_fc.sv
//
// ─── Modifications ──────────────────────────────────────────────
//
//   1. Renamed module: syn_access → syn_access_fc.
//      Distinguishes the FC-layer version from syn_access_cnn
//      (which adds per-window rd_en for convolutional layers).
//
//   2. Removed outspk port.
//      Original: outspk = |inspk_q3 (OR of all delayed spikes).
//      No longer needed — LIF operates in activation-only mode.
//
//   3. Changed rst_acc trigger condition.
//      Original: rst_acc = |(~inspk_q3 & inspk_q2)
//        Only detected rising edges (0→1 transitions).
//        Missed falling edges: if a spike disappeared (1→0),
//        the accumulator was NOT reset, so stale partial sums
//        from the old spike pattern persisted.
//      Modified: rst_acc = |(inspk_q2 ^ inspk_q3)
//        Detects ANY change (both 0→1 and 1→0).
//        Accumulator resets on every spike pattern change.
//
// ─── Description ────────────────────────────────────────────────
//
//   Address generator and MAC controller for the FC layer.
//   One instance per neuron (inside cuba_lif / fc_layer).
//
//   Operation:
//     1. Input spikes pass through a 3-stage delay chain
//        (inspk → inspk_q1 → inspk_q2 → inspk_q3) on memclk.
//     2. When inspk_q2 ≠ inspk_q3 (any bit changed), rst_acc fires.
//        This clears the MAC accumulator in bmem_fc.
//     3. A countdown counter (addr_cnt) sweeps from FANIN-1 down to 0,
//        generating one read address per memclk cycle.
//     4. rd_en gates each address: only active if inspk_q3[addr_cnt] = 1
//        (the pre-synaptic neuron at that address has spiked).
//        Positions without spikes skip the memory read.
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   FANIN        Number of pre-synaptic connections (weight count)
//   ADDR_WIDTH   clog2(FANIN) — memory address width
//
// ─── Ports ──────────────────────────────────────────────────────
//
//   rst          Async reset (clears delay chain, counter, cnt_en)
//   memclk       Memory clock (drives delay chain and address counter)
//   inspk        Input spikes [FANIN-1:0] from pre-synaptic neurons
//   rst_acc      Accumulator reset pulse — fires when inspk changes
//   rd_en        Read enable — high when addr_cnt points to an active spike
//   rd_addr      Read address [ADDR_WIDTH-1:0] — countdown from FANIN-1 to 0
//
// ─── Note ───────────────────────────────────────────────────────
//
//   changed and new_nonzero wires (lines 48-49) are declared but
//   currently unused. They can be removed or used for future
//   enhancements to the trigger logic.
//
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module syn_access_fc #(
	parameter FANIN 	= 5, 		//fanin of the layer
	localparam ADDR_WIDTH 	= $clog2(FANIN)	//synaptic memory address width
)(
	input rst,			//reset
	input memclk,			//clock
	input [FANIN-1:0] inspk,	//input spikes from pre-synaptic connections
	// output outspk,			//output spike to the bmem and LIF module
	output rst_acc,			//reset for the accumulator
	output rd_en,			//read enable
	output [ADDR_WIDTH-1:0] rd_addr //address to read from the synaptic memory 	
);
	

	reg [FANIN-1:0] inspk_q1, inspk_q2, inspk_q3;	//delayed version of the spikes
	reg cnt_en;				//enable counting of memory read accesses
	reg [ADDR_WIDTH-1:0] addr_cnt;		//address counter
	wire changed;
	wire new_nonzero;

	//delay spikes by two clock cycles and check if the input has changed.
	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			inspk_q1 <= 0;
			inspk_q2 <= 0;
			inspk_q3 <= 0;
		end
		else begin
			inspk_q1 <= inspk;
			inspk_q2 <= inspk_q1;
			inspk_q3 <= inspk_q2;
		end
	end

	//address counter: a countdown counter counting from FANIN-1:0.
	always @(posedge memclk or posedge rst) begin
		if (rst) begin
			cnt_en 	 <= 1'b0;
			addr_cnt <= 0;
		end
		else begin
			if (rst_acc) begin
				cnt_en 	 <= 1'b1;
				addr_cnt <= FANIN-1;
			end
			else begin
				if (addr_cnt > 0) begin
					cnt_en   <= 1'b1;
					addr_cnt <= addr_cnt - 1;
				end
				else begin
					cnt_en   <= 1'b0;
				end
			end
		end
	end


	// assign outspk 	= |inspk_q3;			//OR of all spikes.
//	assign rst_acc 	= |(~inspk_q3 & inspk_q2);	//see if any of the spike input has changed. The accumulator needs to be reset if the input spikes changes.
	assign rst_acc = |(inspk_q2 ^ inspk_q3);  //This might give better answer bu did not try it !
	assign rd_en 	= cnt_en & inspk_q3[addr_cnt];	//read enable.
    assign rd_addr 	= addr_cnt;			//the address counter can be used as the memory read address.	

endmodule
