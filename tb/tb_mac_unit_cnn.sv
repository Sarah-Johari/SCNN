/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

File     : tb_bram_rd_mux.sv
// Desc     : Testbench for bram_rd_mux module.
//            Fills bram_rd_data with distinct values, sweeps phase_cnt,
//            prints mac_rd_data to verify correct mux selection.
//
//   Parameters: OUT_CHANNEL=8, IN_CHANNEL=2, P=4 → NUM_PHASES=2
//   bram_rd_data[oc][ic] = (oc * 10) + ic
//     phase 0 → mac units see OC [0,1,2,3]
//     phase 1 → mac units see OC [4,5,6,7]
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module mac_unit_cnn_tb;

    // ── parameters ──
    localparam X_FANIN              = 4;
    localparam Y_FANIN              = 5;
    localparam X_KERNEL             = 2;
    localparam Y_KERNEL             = 3;
    localparam STRIDE               = 1;
    localparam INTEGER_PRECISION    = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_INTEGER_PRECISION = 2;
    localparam X_FANOUT             = ((X_FANIN - X_KERNEL) / STRIDE) + 1;
    localparam Y_FANOUT             = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;
    localparam FANOUT               =  X_FANOUT * Y_FANOUT;
    localparam WT_PRECISION         = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION);
    localparam PRECISION            = (1 + INTEGER_PRECISION + DECIMAL_PRECISION);
    

    // Clocks
    reg memclk = 0;
    reg spkclk = 0;

    always #5  memclk = ~memclk;   // 100 MHz
    always #20 spkclk = ~spkclk;   // 25 MHz
 
    // DUT signals
    reg                       rst;
    reg  [WT_PRECISION-1:0]   rd_data;
    reg  [FANOUT-1:0]         rd_en;
    reg  [FANOUT-1:0]         rst_acc;
    reg  [FANOUT-1:0]         inspk;
    wire [FANOUT-1:0]         outspk;
    wire [PRECISION-1:0]      activation [FANOUT-1:0];
    // Instantiate DUT
    mac_unit_cnn #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION)
    ) dut (
        .rst(rst),
        .memclk(memclk),
        .spkclk(spkclk),
        .rd_data(rd_data),
        .rd_en(rd_en),
        .rst_acc(rst_acc),
        .inspk(inspk),
        .outspk(outspk),
        .activation(activation)
    );


    // main
    initial begin
        
        // Initialize
        rst     = 0;
        rd_data = 0;
        rd_en   = 0;
        rst_acc = 0;
        inspk   = 0;
    
        // Reset
        @(posedge memclk);
        rst = 1;
        @(posedge memclk);
        rst = 0;

        // Clear accumulators first
        @(posedge memclk);
        rst_acc <= {FANOUT{1'b1}};
        @(posedge memclk);
        rst_acc <= 0;

        
        rd_en   <= {FANOUT{1'b1}};
        @(posedge memclk)
        rd_data <= 7'd5;
        inspk   <= {FANOUT{1'b1}};
        repeat(3) @(posedge memclk);
        rd_en <= 0;
        rd_data <= 0;


        repeat(2) @(posedge spkclk);

        @(posedge memclk);
        rst_acc <= {FANOUT{1'b1}};
        @(posedge memclk);
        rst_acc <= 0;

        
        // ── Test 3: Selective rd_en = 0101 (windows 0,2 only) ──
        rd_data = 7'd3;
        rd_en   = 4'b0101;  // only windows 0 and 2
        repeat(2) @(posedge memclk);
        rd_en = 0;
        rd_data = 0;
 
        repeat(2) @(posedge spkclk);



    end 

endmodule