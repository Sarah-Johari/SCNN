/* -----------------------------------------------------------------------------
// File     : tb_bias_controller.sv
// Desc     : Testbench for bias_controller module.
//
//   Test 1: Write + Phase mux — correct bias selected per phase_cnt
//   Test 2: Gating — zero before spikes, values after spikes
//   Test 3: rst_neuron — clears gating latch
//
//   Parameters: OUT_CHANNEL=8, IN_CHANNEL=4, P=4 → NUM_PHASES=2
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module bias_controller_tb;

    // ── parameters ──
    localparam OUT_CHANNEL       = 8;
    localparam IN_CHANNEL        = 4;
    localparam P                 = 4;
    localparam INTEGER_PRECISION = 3;
    localparam DECIMAL_PRECISION = 4;
    localparam X_FANIN           = 4;
    localparam Y_FANIN           = 5;
    localparam FANIN             = X_FANIN * Y_FANIN;  // 20
    localparam PRECISION         = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;  // 8
    localparam OUT_CH_WIDTH      = $clog2(OUT_CHANNEL);  // 3
    localparam NUM_PHASES        = (OUT_CHANNEL + P - 1) / P;  // 2
    localparam PHASE_WIDTH       = $clog2(NUM_PHASES);  // 1

    
    // ── clocks ──
    localparam MEMCLK_PERIOD = 10;  // 100 MHz
    localparam SPKCLK_PERIOD = 40;  // 25 MHz (slower spike clock)
 
    reg memclk = 0;
    reg spkclk = 0;
    always #(MEMCLK_PERIOD/2) memclk = ~memclk;
    always #(SPKCLK_PERIOD/2) spkclk = ~spkclk;

    // ── DUT signals ──
    reg                        rst, rst_neuron;
    reg                        bias_wr_en;
    reg  [OUT_CH_WIDTH-1:0]    bias_wr_addr;
    reg  [PRECISION-1:0]       bias_wr_data;
    reg  [FANIN-1:0]           inspk [IN_CHANNEL-1:0];
    reg  [PHASE_WIDTH-1:0]     phase_cnt;
    wire [PRECISION-1:0]       active_bias [P-1:0];

    // Instantiate DUT
    bias_controller #(
        .OUT_CHANNEL(OUT_CHANNEL),
        .IN_CHANNEL(IN_CHANNEL),
        .P(P),
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) dut (
        .rst(rst),
        .rst_neuron(rst_neuron),
        .memclk(memclk),
        .spkclk(spkclk),
        .bias_wr_en(bias_wr_en),
        .bias_wr_addr(bias_wr_addr),
        .bias_wr_data(bias_wr_data),
        .inspk(inspk),
        .phase_cnt(phase_cnt),
        .active_bias(active_bias)
    );

    //helper task
    task automatic write_bias(
        input [OUT_CH_WIDTH-1:0] addr,
        input [PRECISION-1:0]    data 
    );
        @(posedge memclk);
        bias_wr_en   <= 1;
        bias_wr_addr <= addr;
        bias_wr_data <= data;

        @(posedge memclk);
        bias_wr_en   <= 0;

    endtask


    // main
    initial begin
         
    rst        = 0;
    rst_neuron = 0;
    bias_wr_en = 0;
    phase_cnt  = 0;
    for (int i = 0; i < IN_CHANNEL; i++) begin
        inspk[i] = '0;
    end  
    
    
    @(posedge memclk);
    rst = 1;
    @(posedge memclk);
    rst = 0;
    
    for (int oc = 0 ; oc < OUT_CHANNEL; oc++) begin
        write_bias ( oc[OUT_CH_WIDTH-1:0] ,  (oc + 1) * 10);
    end 
    #1;
    // Enable gating first (need a spike)
    inspk[0] = 20'h1;
    repeat(2) @(posedge spkclk); 
    #1;
    phase_cnt = 0; 
    #1;
    phase_cnt = 1;
    #1;
    #SPKCLK_PERIOD;
    @(posedge memclk);
    rst = 1;
    @(posedge memclk);
    rst = 0;

    for (int i = 0; i < IN_CHANNEL; i++) begin
        inspk[i] = '0;
    end
    
    @(posedge spkclk);
    phase_cnt = 0;
    
    @(posedge spkclk);
    phase_cnt = 1;
    
//    $finish;  
    end

endmodule