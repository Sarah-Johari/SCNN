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
// File     	: tb_pooling.sv
// Desc     	: 
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module pooling_tb;

    // Parameters (match the DUT)
    localparam X_FANIN           = 4;
    localparam Y_FANIN           = 5;
    localparam POOL_X_KERNEL     = 1;
    localparam POOL_Y_KERNEL     = 1;
    localparam POOL_STRIDE       = 1;
    localparam OUT_CHANNEL       = 1;
    localparam POOL_MODE         = 2;
    localparam INTEGER_PRECISION = 3;
    localparam DECIMAL_PRECISION = 4;

    localparam FANIN            = X_FANIN * Y_FANIN;
    localparam PRECISION        = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;
    localparam X_FANOUT         = ((X_FANIN - POOL_X_KERNEL) / POOL_STRIDE) + 1;
    localparam Y_FANOUT         = ((Y_FANIN - POOL_Y_KERNEL) / POOL_STRIDE) + 1;
    localparam FANOUT           = X_FANOUT * Y_FANOUT;

    // DUT signals
    reg clk;
    reg rst;

    reg [PRECISION-1:0] act_in [OUT_CHANNEL-1:0][FANIN-1:0];
    reg [PRECISION-1:0] act_o  [OUT_CHANNEL-1:0][FANOUT-1:0];

    // Instantiate DUT
    pooling #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .POOL_X_KERNEL(POOL_X_KERNEL),
        .POOL_Y_KERNEL(POOL_Y_KERNEL),
        .POOL_STRIDE(POOL_STRIDE),
        .OUT_CHANNEL(OUT_CHANNEL),
        .POOL_MODE(POOL_MODE),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) pooling_dut (
        .rst(rst),
        .clk(clk),
        .activation_in(act_in),
        .activation_out(act_o)
    );

    task automatic random_input();
        for (int c = 0 ; c < OUT_CHANNEL ; c++) begin
            for (int i = 0 ; i < FANIN ; i++) begin
                act_in[c][i] = $random;
            end 
        end 
    endtask
    // Clock generation: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // Test stimulus
    initial begin
        rst =1;
        @(posedge clk); #1;
        rst = 0;

        for (int c = 0; c < OUT_CHANNEL; c++)
            for (int i = 0; i < FANIN; i++)
                act_in[c][i] = '0;

        
        for (int trial = 0; trial < 5; trial++) begin
            @(posedge clk); #1;
            random_input();
        end 
        $display("\n=== pooling Test Completed ===");
//        $finish;
    end

endmodule