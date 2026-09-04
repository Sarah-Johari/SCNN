/* -----------------------------------------------------------------------------
// File     : tb_cnn_layer_folded.sv
// Desc     : Testbench for cnn_layer_folded module.
//
//   1. Reset
//   2. Write uniform weights (all = 1) to all BRAMs
//   3. Write biases (bias[oc] = oc + 1)
//   4. Apply input spikes
//   5. Wait for phase_done
//   6. Print captured_activation, outspk
//
//   Parameters: IN_CHANNEL=2, OUT_CHANNEL=8, P=4 → NUM_PHASES=2
//   FANOUT=9, MEM_SIZE=6, WT_PRECISION=7, PRECISION=8
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module tb_cnn_layer_folded;

    localparam X_FANIN              = 4;
    localparam Y_FANIN              = 5;
    localparam X_KERNEL             = 2;
    localparam Y_KERNEL             = 3;
    localparam POOL_X_KERNEL        = 1;
    localparam POOL_Y_KERNEL        = 1;
    localparam STRIDE               = 1;
    localparam POOL_STRIDE          = 1;
    localparam POOL_MODE            = 2;  
    localparam IN_CHANNEL           = 2;
    localparam OUT_CHANNEL          = 8;
    localparam P                    = 4;
    localparam INTEGER_PRECISION    = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_INTEGER_PRECISION = 2;
    localparam IN_CH_ADDR_START     = 3;
    localparam OUT_CH_ADDR_START    = 4;
    localparam ADDR_WIDTH           = 10;
    localparam X_FANOUT             = ((X_FANIN - X_KERNEL) / STRIDE) + 1;
    localparam Y_FANOUT             = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1;
    localparam FANOUT               = X_FANOUT * Y_FANOUT;         // 9
    localparam MEM_SIZE             = X_KERNEL * Y_KERNEL;          // 6
    localparam ADDR_WIDTH_MEM       = $clog2(MEM_SIZE);             // 3
    localparam FANIN                = X_FANIN * Y_FANIN;            // 20
    localparam IN_CH_WIDTH          = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL);       // 1
    localparam OUT_CH_WIDTH         = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL);           // 3
    localparam WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION;  // 7
    localparam PRECISION            = 1 + INTEGER_PRECISION + DECIMAL_PRECISION;      // 8

    // Clocks
    reg memclk = 0;
    reg spkclk = 0;
    always #5  memclk = ~memclk;   // 100 MHz
    always #20 spkclk = ~spkclk;   // 25 MHz

    // DUT signals
    reg                        rst;
    reg                        rst_neuron;
    reg  [PRECISION-1:0]       vth;
    reg  [PRECISION-1:0]       decay_rate;
    reg  [PRECISION-1:0]       grow_rate;
    reg  [PRECISION-1:0]       vrest;
    reg  [PRECISION-1:0]       reset_mechanism;
    reg  [PRECISION-1:0]       refractory_period;
    reg                        wr_en;
    reg  [ADDR_WIDTH-1:0]      wr_addr;
    reg  [WT_PRECISION-1:0]    wr_data;
    reg                        bias_wr_en;
    reg  [OUT_CH_WIDTH-1:0]    bias_wr_addr;
    reg  [PRECISION-1:0]       bias_wr_data;
    reg  [FANIN-1:0]           inspk [IN_CHANNEL-1:0];
    wire [PRECISION-1:0]       vmem [OUT_CHANNEL-1:0][FANOUT-1:0];
    wire [FANOUT-1:0]          outspk [OUT_CHANNEL-1:0];
    wire                       phase_done;

    // Instantiate DUT
    cnn_layer_folded #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .POOL_X_KERNEL(POOL_X_KERNEL),
        .POOL_Y_KERNEL(POOL_Y_KERNEL),
        .STRIDE(STRIDE),
        .POOL_STRIDE(POOL_STRIDE),
        .POOL_MODE(POOL_MODE),
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL),
        .IN_CH_ADDR_START(IN_CH_ADDR_START),
        .OUT_CH_ADDR_START(OUT_CH_ADDR_START),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
        .ADDR_WIDTH(ADDR_WIDTH),
        .P(P)
    ) dut (
        .rst(rst),
        .rst_neuron(rst_neuron),
        .memclk(memclk),
        .spkclk(spkclk),
        .vth(vth),
        .decay_rate(decay_rate),
        .grow_rate(grow_rate),
        .vrest(vrest),
        .reset_mechanism(reset_mechanism),
        .refractory_period(refractory_period),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .bias_wr_en(bias_wr_en),
        .bias_wr_addr(bias_wr_addr),
        .bias_wr_data(bias_wr_data),
        .inspk(inspk),
        .vmem(vmem),
        .outspk(outspk),
        .phase_done(phase_done)
    );

    // ── Helper: write one weight to BRAM[oc][ic] at address k ──
    task automatic write_weight(
        input [OUT_CH_WIDTH-1:0]   oc,
        input [IN_CH_WIDTH-1:0]    ic,
        input [ADDR_WIDTH_MEM-1:0] k,
        input [WT_PRECISION-1:0]   weight
    );
        @(posedge memclk);
        wr_en   <= 1;
        wr_addr <= '0;
        wr_addr[ADDR_WIDTH_MEM-1:0]                    <= k;
        wr_addr[IN_CH_ADDR_START  +: IN_CH_WIDTH]      <= ic;
        wr_addr[OUT_CH_ADDR_START +: OUT_CH_WIDTH]     <= oc;
        wr_data <= weight;
        @(posedge memclk);
        wr_en   <= 0;
    endtask

    // ── Helper: write one bias ──
    task automatic write_bias(
        input [OUT_CH_WIDTH-1:0] oc,
        input [PRECISION-1:0]    bias
    );
        @(posedge memclk);
        bias_wr_en   <= 1;
        bias_wr_addr <= oc;
        bias_wr_data <= bias;
        @(posedge memclk);
        bias_wr_en   <= 0;
    endtask

    // Monitor phase_done
    always @(posedge memclk) begin
        if (phase_done)
            $display("  [%0t] phase_done fired", $time);
    end

    // Main test
    initial begin
        $display("\n=== cnn_layer_folded Testbench ===");
        $display("IN_CHANNEL=%0d, OUT_CHANNEL=%0d, P=%0d, FANOUT=%0d, MEM_SIZE=%0d\n",
                 IN_CHANNEL, OUT_CHANNEL, P, FANOUT, MEM_SIZE);

        // Initialize
        rst              = 0;
        rst_neuron       = 0;
        wr_en            = 0;
        bias_wr_en       = 0;
        wr_addr          = '0;
        wr_data          = '0;
        bias_wr_addr     = '0;
        bias_wr_data     = '0;
        vth              = 8'd100;
        decay_rate       = 8'd1;
        grow_rate        = 8'd1;
        vrest            = 8'd0;
        reset_mechanism  = 8'd0;
        refractory_period= 8'd0;
        for (int i = 0; i < IN_CHANNEL; i++) inspk[i] = '0;

        // Reset
        @(posedge memclk);
        rst = 1;
        repeat(3) @(posedge memclk);
        repeat(2) @(posedge spkclk);
        rst = 0;
        repeat(2) @(posedge memclk);

        // ── Step 1: Write weights (all = 1) to all BRAMs ────
        $display("Step 1: Writing weights (all = 1)...");
        for (int oc = 0; oc < OUT_CHANNEL; oc++) begin
            for (int ic = 0; ic < IN_CHANNEL; ic++) begin
                for (int k = 0; k < MEM_SIZE; k++) begin
                    write_weight(oc[OUT_CH_WIDTH-1:0], ic[IN_CH_WIDTH-1:0],
                                 k[ADDR_WIDTH_MEM-1:0], 7'd1);
                end
            end
        end
        $display("  Done. Wrote %0d weights.", OUT_CHANNEL * IN_CHANNEL * MEM_SIZE);

        // ── Step 2: Write biases (bias[oc] = oc + 1) ────────
        $display("\nStep 2: Writing biases...");
        for (int oc = 0; oc < OUT_CHANNEL; oc++) begin
            write_bias(oc[OUT_CH_WIDTH-1:0], (oc + 1));
        end
        $display("  Done. Biases = [1, 2, 3, 4, 5, 6, 7, 8]");

        // ── Step 3: Apply input spikes ───────────────────────
        // Channel 0: spikes at (0,0) and (1,1)
        // Channel 1: spike at (2,3)
        $display("\nStep 3: Applying input spikes...");
        inspk[0] = '0;
        inspk[1] = '0;
        inspk[0][0*Y_FANIN + 0] = 1'b1;  // (0,0)
        inspk[0][1*Y_FANIN + 1] = 1'b1;  // (1,1)
        inspk[1][2*Y_FANIN + 3] = 1'b1;  // (2,3)
        $display("  ch0: spikes at (0,0) and (1,1)");
        $display("  ch1: spike at (2,3)");

        // ── Step 4: Wait for processing ──────────────────────
        $display("\nStep 4: Waiting for phase_done...");
        @(posedge phase_done);
        repeat(2) @(posedge memclk);

        // Wait for CDC + pooling + LIF to propagate
        repeat(8) @(posedge spkclk);

        // ── Step 5: Print results ────────────────────────────
        $display("\nStep 5: Results");

        // Print captured_activation for each output channel
        $display("\n  captured_activation (first 4 windows per OC):");
        for (int oc = 0; oc < OUT_CHANNEL; oc++) begin
            $display("    OC%0d: [%0d, %0d, %0d, %0d ...]",
                     oc,
                     dut.captured_activation[oc][0],
                     dut.captured_activation[oc][1],
                     dut.captured_activation[oc][2],
                     dut.captured_activation[oc][3]);
        end

        // Print outspk
        $display("\n  outspk:");
        for (int oc = 0; oc < OUT_CHANNEL; oc++) begin
            $display("    OC%0d: %b", oc, outspk[oc]);
        end

        // Print vmem for first output channel
        $display("\n  vmem[0] (all windows):");
        for (int w = 0; w < FANOUT; w++) begin
            $display("    win%0d: %0d", w, vmem[0][w]);
        end

        $display("\nDone.\n");
        $finish;
    end

endmodule