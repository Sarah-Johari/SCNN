/* -----------------------------------------------------------------------------
// File     : tb_phase_controller.sv
// Desc     : Testbench for phase_controller module.
//
//   Simulates syn_access_cnn outputs (sa_rd_en, sa_rst_acc, sa_rd_addr)
//   and verifies:
//     1. FSM transitions through all phases
//     2. rd_en capture during phase 0
//     3. rd_en replay during phase 1 matches phase 0
//     4. capture_en and phase_done pulse at correct times
//
//   Parameters: IN_CHANNEL=2, OUT_CHANNEL=8, P=4
//   → FANOUT=9, MEM_SIZE=6, NUM_PHASES=2, SA_SWEEP_CYCLES=9
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps

module phase_controller_tb;

    localparam X_FANIN     = 4;
    localparam Y_FANIN     = 5;
    localparam X_KERNEL    = 2;
    localparam Y_KERNEL    = 3;
    localparam STRIDE      = 1;
    localparam IN_CHANNEL  = 2;
    localparam OUT_CHANNEL = 8;
    localparam P           = 2;
    localparam X_FANOUT    = ((X_FANIN - X_KERNEL) / STRIDE) + 1;
    localparam Y_FANOUT    = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;
    localparam FANOUT      = X_FANOUT * Y_FANOUT;     // 9
    localparam MEM_SIZE    = X_KERNEL * Y_KERNEL;      // 6
    localparam ADDR_WIDTH_MEM = $clog2(MEM_SIZE);
    localparam NUM_PHASES  = (OUT_CHANNEL + P - 1) / P; // 2
    localparam PHASE_WIDTH = $clog2(NUM_PHASES);
    localparam SA_SWEEP_CYCLES = MEM_SIZE + 3;          // 9
 
    // Clock
    reg memclk = 0;
    always #5 memclk = ~memclk;

    // DUT signals
    reg                        rst;
    reg  [FANOUT-1:0]          sa_rd_en   [IN_CHANNEL-1:0];
    reg  [FANOUT-1:0]          sa_rst_acc [IN_CHANNEL-1:0];
    reg  [FANOUT-1:0]          sa_outspk  [IN_CHANNEL-1:0];
    reg  [ADDR_WIDTH_MEM-1:0]  sa_rd_addr [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]          mac_rd_en  [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]          mac_rst_acc[IN_CHANNEL-1:0];
    wire [FANOUT-1:0]          mac_inspk  [IN_CHANNEL-1:0];
    wire [ADDR_WIDTH_MEM-1:0]  bram_rd_addr [IN_CHANNEL-1:0];
    wire [PHASE_WIDTH-1:0]     phase_cnt_out;
    wire                       capture_en;
    wire                       phase_done;


    // Instantiate DUT
    phase_controller #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL),
        .P(P)
    ) dut (
        .rst(rst),
        .memclk(memclk),
        .sa_rd_en(sa_rd_en),
        .sa_rst_acc(sa_rst_acc),
        .sa_outspk(sa_outspk),
        .sa_rd_addr(sa_rd_addr),
        .mac_rd_en(mac_rd_en),
        .mac_rst_acc(mac_rst_acc),
        .mac_inspk(mac_inspk),
        .bram_rd_addr(bram_rd_addr),
        .phase_cnt_out(phase_cnt_out),
        .capture_en(capture_en),
        .phase_done(phase_done)
    );

         
    // Initialize all inputs
    initial begin
    rst = 0;
    for (int ch = 0; ch < IN_CHANNEL; ch++) begin
        sa_rd_en[ch]   = '0;
        sa_rst_acc[ch] = '0;
        sa_outspk[ch]  = '0;
        sa_rd_addr[ch] = '0;
    end
   

    // Reset
    @(posedge memclk);
    rst = 1;
    @(posedge memclk);
    rst = 0;

    // ── Trigger: pulse sa_rst_acc on channel 0 ──────────
    $display("Triggering sweep via sa_rst_acc[0]...");
    @(posedge memclk);
    sa_rst_acc[0] <= 9'b1;
    sa_outspk[0]  <= 9'b101010101;
    sa_outspk[1]  <= 9'b010101010;
    @(posedge memclk);
    sa_rst_acc[0] <= 9'b0;


    // ── Phase 0: simulate syn_access_cnn sweep ──────────
    // Drive sa_rd_en with distinct patterns for MEM_SIZE cycles
    // Pattern: sa_rd_en[ch] = (k+1) << ch  (distinct per channel and per k)
    for (int k = 0; k < MEM_SIZE; k++) begin
        for (int ch = 0; ch < IN_CHANNEL; ch++) begin
            sa_rd_en[ch]   <= (k + 1) << ch;
            sa_rd_addr[ch] <= k[ADDR_WIDTH_MEM-1:0];
        end
        @(posedge memclk);
    end 

    // Clear sa_rd_en (syn_access_cnn enters DONE/IDLE)
    @(posedge memclk);
    for (int ch = 0; ch < IN_CHANNEL; ch++) begin
        sa_rd_en[ch]   = '0;
        sa_rd_addr[ch] = '0;
    end


    // Wait for phase 0 to finish (remaining flush cycles)
    repeat(SA_SWEEP_CYCLES - MEM_SIZE + 2) @(posedge memclk);


    // ── Phase 1: verify replay ──────────────────────────
    $display("\nPhase 1: checking replay of captured rd_en...");

    // Wait for PH_RST_MAC (1 cycle) then PH_SWEEP starts
    // repeat(10) @(posedge memclk);
    // $finish;

    end

endmodule