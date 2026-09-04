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
// Author   	: Sarah Johari
// Email    	: sj984@drexel.edu
// Date     	: Aug 05, 2025
// File     	: tb_feature_map.sv
// Desc     	: 
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module feature_map_tb;

    // Parameters (match the DUT)
    localparam X_FANIN           = 16;
    localparam Y_FANIN           = 16;
    localparam X_KERNEL          = 5;
    localparam Y_KERNEL          = 5;
    localparam STRIDE            = 1;
    localparam INTEGER_PRECISION = 3;
    localparam DECIMAL_PRECISION = 4;
    localparam ADDR_WIDTH_NEURON = 10;
    localparam ADDR_WIDTH_FANIN  = 10;

    localparam FANIN             = X_FANIN * Y_FANIN;
    localparam PRECISION         = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;
    localparam WT_PRECISION      = 1 + DECIMAL_PRECISION;
    localparam FANOUT_X          = ((X_FANIN - X_KERNEL) / STRIDE) + 1;
    localparam FANOUT_Y          = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;
    localparam FANOUT_FM         = FANOUT_X * FANOUT_Y;
    localparam ADDR_WIDTH        = ADDR_WIDTH_NEURON + ADDR_WIDTH_FANIN;

    // DUT signals
    reg clk_mem;
    reg clk_spk;
    reg rst;
    reg wr_en;
    reg [ADDR_WIDTH-1:0] wr_addr = 0;
    reg [WT_PRECISION-1:0] wr_data = 0;
    reg [FANIN-1:0] inspk = 0;
    reg [ADDR_WIDTH_NEURON-1:0] monitor_id = 0;

    reg  [PRECISION-1:0] vth = 0;
    reg  [PRECISION-1:0] decay_rate = 0;
    reg  [PRECISION-1:0] grow_rate = 0;
    reg  [PRECISION-1:0] vrest = 0;
    reg  [PRECISION-1:0] reset_mechanism = 0;
    reg  [PRECISION-1:0] refractory_period = 0;

    wire [FANOUT_FM-1:0] outspk;
    wire [PRECISION-1:0] vmem[FANOUT_FM-1:0];

    // Instantiate DUT
    feature_map #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) dut (
        .rst(rst),
        .memclk(clk_mem),
        .spkclk(clk_spk),
        .vth(vth),
        .decay_rate(decay_rate),
        .grow_rate(grow_rate),
        .vrest(vrest),
        .reset_mechanism(reset_mechanism),
        .refractory_period(refractory_period),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .inspk(inspk),
        // .monitor_id(monitor_id),
        .outspk(outspk),
        .vmem(vmem)
    );

    // Clock generation: 10ns period
    always #5 clk_mem = ~clk_mem;
    always #18100 clk_spk = ~clk_spk; // offset clock for spiking

    // Test stimulus
    initial begin
        $display("=== feature_map Test Start ===");

        // Reset and wait
        clk_spk = 0;
        clk_mem = 0;
        rst = 1;
        inspk = 0;
        wr_en = 0;
        #20;
        rst = 0;

        // Initialize neuron parameters
        vth = 5;
        decay_rate = 1;
        grow_rate = 2;
        vrest = 0;
        reset_mechanism = 2;
        refractory_period = 0;
        monitor_id = 2;

        // Write dummy synaptic weights (optional)
        wr_en = 1;
        wr_addr = 0;
        wr_data = 32'h000001fb;
        #10;
		wr_addr = 1;
		wr_data = 32'h00000021;
		#10;
		wr_addr = 2;
		wr_data = 32'h000001ed;
		#10;
		wr_addr = 3;
		wr_data = 32'h00000018;
		#10;
		wr_addr = 4;
		wr_data = 32'h00000022;
		#10;
		wr_addr = 5;
		wr_data = 32'h0000000d;
		#10;;
        wr_addr = 6;
        wr_data = 32'h00000010;
        #10;
		wr_addr = 7;
		wr_data = 32'h000001ef;
		#10;
		wr_addr = 8;
		wr_data = 32'h000001f2 ;
		#10;
		wr_addr = 9;
		wr_data = 32'h000001df;
		#10;
		wr_addr = 10;
		wr_data = 32'h0000002a;
		#10;
		wr_addr = 11;
		wr_data = 32'h000001ff;
		#10;
        wr_addr = 12;
		wr_data = 32'h00000026;
		#10;
        wr_addr = 13;
		wr_data = 32'h00000029;
		#10;
        wr_addr = 14;
		wr_data = 32'h0000001c;
		#10;
        wr_addr = 15;
		wr_data = 32'h000001fa;
		#10;
        wr_addr = 16;
		wr_data = 32'h00000028;
		#10;
        wr_addr = 17;
		wr_data = 32'h000001df;
		#10;
        wr_addr = 18;
		wr_data = 32'h00000012;
		#10;
        wr_addr = 19;
		wr_data = 32'h000001da;
		#10;
        wr_addr = 20;
		wr_data = 32'h000001ba;
		#10;
        wr_addr = 21;
		wr_data = 32'h000001ca;
		#10;
        wr_addr = 22;
		wr_data = 32'h00000016;
		#10;
        wr_addr = 23;
		wr_data = 32'h0000001e;
		#10;
        wr_addr = 24;
		wr_data = 32'h000001fa;
		#10;
        wr_en = 0;



        // Apply input spikes
		inspk = 0;


        // #50; inspk = 20'b00000000001111111111;       ////  outputs 1 and 2 spike
        @(posedge clk_spk)
        inspk = 256'b0000000000000000000000000000000000000000000000000000000000000000000001111100000000001111101100000011010100110000001110000011000000000000001000000000000001100000000000000111000000000000010000000000000100000000000000010000000000000010000000000000000000000000; 
        // #50; inspk = 20'b11111111110000000000;      ////  outputs 2 and 3 spike
        // #50; inspk = 20'b11111111111111111111;      //// all outputs spike

        @(posedge clk_spk)
        inspk = 0;

        // Monitor vmem and output spikes
        monitor_id = 0;

        // Wait to observe output
        repeat (50) @(posedge clk_spk);

        $display("=== feature_map Test Completed ===");
        //$finish;
    end

endmodule