/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2023 Drexel University

// Author       : Sarah Johari (original cnn_layer), refactored for output-channel folding
// Date         : May 2026
// File         : cnn_layer_folded.sv
// Desc         : Output-channel-folded spiking convolutional layer (modular version).
//
//   Sub-modules:
//     bram_store_cnn   : BRAM weight storage         [OUT_CHANNEL × IN_CHANNEL]
//     mac_unit_cnn     : MAC datapath + CDC           [P × IN_CHANNEL]
//     syn_access_cnn   : Read address sequencer       [IN_CHANNEL]
//     phase_controller : Phase FSM + MAC ctrl signals [1]
//     bram_rd_mux      : BRAM→MAC data mux            [1]
//     bias_controller  : Bias storage + gating + mux  [1]
//     xchan_bias_acc   : Cross-channel acc + bias      [1]
//     pooling          : Activation pooling            [1]
//     lif              : LIF neurons                   [OUT_CHANNEL × FANOUT]
//
//   Data flow:
//     inspk → syn_access_cnn → bram_store_cnn (muxed) → mac_unit_cnn
//     → xchan_bias_acc → capture regs → pooling → lif
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

`include "defines.vh"

module cnn_layer_folded #(
    parameter X_FANIN              = 4,
    parameter Y_FANIN              = 5,
    parameter X_KERNEL             = 2,
    parameter Y_KERNEL             = 3,
    parameter POOL_X_KERNEL        = 1,
    parameter POOL_Y_KERNEL        = 1,
    parameter STRIDE               = 1,
    parameter POOL_STRIDE          = 1,
    parameter POOL_MODE            = 1,
    parameter IN_CHANNEL           = 1,
    parameter OUT_CHANNEL          = 1,
    parameter IN_CH_ADDR_START     = 1,
    parameter OUT_CH_ADDR_START    = 1,
    parameter INTEGER_PRECISION    = 7,
    parameter DECIMAL_PRECISION    = 8,
    parameter WT_INTEGER_PRECISION = 2,
    parameter ADDR_WIDTH           = 32,
    parameter P                    = 4,

    
    localparam MEM_SIZE        = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM  = $clog2(MEM_SIZE),
    localparam X_FANOUT        = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT        = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT          = X_FANOUT * Y_FANOUT,
    localparam FANIN           = X_FANIN * Y_FANIN,
    localparam POOLED_X_FANOUT = ((X_FANOUT  - POOL_X_KERNEL) / POOL_STRIDE) + 1,
    localparam POOLED_Y_FANOUT = ((Y_FANOUT  - POOL_Y_KERNEL) / POOL_STRIDE) + 1,
    localparam POOLED_FANOUT   = POOLED_X_FANOUT * POOLED_Y_FANOUT,
    localparam IN_CH_WIDTH     = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL),      
    localparam OUT_CH_WIDTH    = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL),          
    localparam WT_PRECISION    = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam PRECISION       = (1 + INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam NUM_PHASES      = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH     = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1
)(
    input  rst,
    input  rst_neuron,
    input  memclk,
    input  spkclk,
    input  [PRECISION-1:0] vth,
    input  [PRECISION-1:0] decay_rate,
    input  [PRECISION-1:0] grow_rate,
    input  [PRECISION-1:0] vrest,
    input  [PRECISION-1:0] reset_mechanism,
    input  [PRECISION-1:0] refractory_period,
    input  wr_en,
    input  [ADDR_WIDTH-1:0] wr_addr,
    input  [WT_PRECISION-1:0] wr_data,
    input  bias_wr_en,
    input  [OUT_CH_WIDTH-1:0] bias_wr_addr,
    input  [PRECISION-1:0] bias_wr_data,
    input  [FANIN-1:0] inspk [IN_CHANNEL-1:0],
    output [PRECISION-1:0] vmem [OUT_CHANNEL-1:0][FANOUT-1:0],
    output [FANOUT-1:0] outspk [OUT_CHANNEL-1:0],
    output phase_done
);


    // ─────────────────────────────────────────────────────────────
    // Neuron config registers (all OUT_CHANNEL kept)
    // ─────────────────────────────────────────────────────────────
    reg [PRECISION-1:0] vth_local              [OUT_CHANNEL-1:0];
    reg [PRECISION-1:0] decay_rate_local       [OUT_CHANNEL-1:0];
    reg [PRECISION-1:0] grow_rate_local        [OUT_CHANNEL-1:0];
    reg [PRECISION-1:0] vrest_local            [OUT_CHANNEL-1:0];
    reg [PRECISION-1:0] reset_mechanism_local  [OUT_CHANNEL-1:0];
    reg [PRECISION-1:0] refractory_period_local[OUT_CHANNEL-1:0];

    genvar cfg_i;
    generate
        for (cfg_i = 0; cfg_i < OUT_CHANNEL; cfg_i = cfg_i + 1) begin : cfg_regs
            always @(posedge memclk or posedge rst) begin
                if (rst) begin
                    vth_local[cfg_i]               <= '0;
                    decay_rate_local[cfg_i]        <= '0;
                    grow_rate_local[cfg_i]         <= '0;
                    vrest_local[cfg_i]             <= '0;
                    reset_mechanism_local[cfg_i]   <= '0;
                    refractory_period_local[cfg_i] <= '0;
                end else begin
                    vth_local[cfg_i]               <= vth;
                    decay_rate_local[cfg_i]        <= decay_rate;
                    grow_rate_local[cfg_i]         <= grow_rate;
                    vrest_local[cfg_i]             <= vrest;
                    reset_mechanism_local[cfg_i]   <= reset_mechanism;
                    refractory_period_local[cfg_i] <= refractory_period;
                end
            end
        end
    endgenerate





    // ─────────────────────────────────────────────────────────────
    // BRAM write decoder
    // ─────────────────────────────────────────────────────────────
    wire [OUT_CHANNEL-1:0][IN_CHANNEL-1:0] wr_addr_decode;
    bram_decoder #(
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL)
    ) wr_addr_decoder (
        .en(wr_en),
        .in_ch(wr_addr[IN_CH_ADDR_START  +: IN_CH_WIDTH]),
        .out_ch(wr_addr[OUT_CH_ADDR_START +: OUT_CH_WIDTH]),
        .bram_sel(wr_addr_decode)
    );


    // ─────────────────────────────────────────────────────────────
    // syn_access_cnn — IN_CHANNEL instances (unchanged)
    // ─────────────────────────────────────────────────────────────
    wire [FANOUT-1:0]         sa_rd_en   [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]         sa_rst_acc [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]         sa_outspk  [IN_CHANNEL-1:0];
    wire [ADDR_WIDTH_MEM-1:0] sa_rd_addr [IN_CHANNEL-1:0];

    genvar ic;
    generate
        for (ic = 0; ic < IN_CHANNEL; ic = ic + 1) begin : syn_acc
            syn_access_cnn #(
                .X_FANIN(X_FANIN),
                .Y_FANIN(Y_FANIN),
                .X_KERNEL(X_KERNEL),
                .Y_KERNEL(Y_KERNEL),
                .STRIDE(STRIDE)
            ) rd_addr_decoder (
                .rst(rst),
                .memclk(memclk),
                .inspk(inspk[ic]),
                .outspk(sa_outspk[ic]),
                .rst_acc(sa_rst_acc[ic]),
                .rd_en(sa_rd_en[ic]),
                .rd_addr(sa_rd_addr[ic])
            );
        end
    endgenerate


    // ─────────────────────────────────────────────────────────────
    // Phase controller (FSM + MAC control + BRAM addr mux)
    // ─────────────────────────────────────────────────────────────
    wire [FANOUT-1:0]      mac_rd_en   [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]      mac_rst_acc [IN_CHANNEL-1:0];
    wire [FANOUT-1:0]      mac_inspk   [IN_CHANNEL-1:0];
    wire [ADDR_WIDTH_MEM-1:0] bram_rd_addr[IN_CHANNEL-1:0];
    wire [PHASE_WIDTH-1:0]    phase_cnt;
    wire                      capture_en;

    phase_controller #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL),
        .P(P)
    ) phase_ctrl (
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
        .phase_cnt_out(phase_cnt),
        .capture_en(capture_en),
        .phase_done(phase_done)
    );


    // ─────────────────────────────────────────────────────────────
    // Bias controller (register file + gating + phase mux)
    // ─────────────────────────────────────────────────────────────
    wire [PRECISION-1:0] active_bias [P-1:0];

    bias_controller #(
        .OUT_CHANNEL(OUT_CHANNEL),
        .IN_CHANNEL(IN_CHANNEL),
        .P(P),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION),
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN)
    ) bias_ctrl (
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
	
	

    // ─────────────────────────────────────────────────────────────
    // BRAM storage — OUT_CHANNEL × IN_CHANNEL (all weights resident)
    // ─────────────────────────────────────────────────────────────
    wire [WT_PRECISION-1:0] bram_rd_data [OUT_CHANNEL-1:0][IN_CHANNEL-1:0];

    genvar oc_b, ic_b;
    generate
        for (oc_b = 0; oc_b < OUT_CHANNEL; oc_b = oc_b + 1) begin : bram_oc
            for (ic_b = 0; ic_b < IN_CHANNEL; ic_b = ic_b + 1) begin : bram_ic
                bram_store_cnn #(
                    .X_KERNEL(X_KERNEL),
                    .Y_KERNEL(Y_KERNEL),
                    .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
                    .DECIMAL_PRECISION(DECIMAL_PRECISION)
                ) bram_inst (
                    .memclk(memclk),
                    .wr_en(wr_addr_decode[oc_b][ic_b]),
                    .wr_addr(wr_addr[ADDR_WIDTH_MEM-1:0]),
                    .wr_data(wr_data),
                    .rd_addr(bram_rd_addr[ic_b]),
                    .rd_data(bram_rd_data[oc_b][ic_b])
                );
            end
        end
    endgenerate


    // ─────────────────────────────────────────────────────────────
    // BRAM→MAC data mux (selects output channel group per phase)
    // ─────────────────────────────────────────────────────────────
    wire [WT_PRECISION-1:0] mac_rd_data [P-1:0][IN_CHANNEL-1:0];

    bram_rd_mux #(
        .P(P),
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) rd_mux (
        .phase_cnt(phase_cnt),
        .bram_rd_data(bram_rd_data),
        .mac_rd_data(mac_rd_data)
    );


    // ─────────────────────────────────────────────────────────────
    // MAC units — P × IN_CHANNEL (shared, area saving)
    // ─────────────────────────────────────────────────────────────
    //wire [FANOUT-1:0]    mac_out_spk    [P-1:0][IN_CHANNEL-1:0];
    wire [PRECISION-1:0] mac_activation [P-1:0][IN_CHANNEL-1:0][FANOUT-1:0];

    genvar u, c;
    generate
        for (u = 0; u < P; u = u + 1) begin : mac_par
            for (c = 0; c < IN_CHANNEL; c = c + 1) begin : mac_ch
                mac_unit_cnn #(
                    .X_FANIN(X_FANIN),
                    .Y_FANIN(Y_FANIN),
                    .X_KERNEL(X_KERNEL),
                    .Y_KERNEL(Y_KERNEL),
                    .STRIDE(STRIDE),
                    .INTEGER_PRECISION(INTEGER_PRECISION),
                    .DECIMAL_PRECISION(DECIMAL_PRECISION),
                    .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION)
                ) mac_inst (
                    .rst(rst),
                    .memclk(memclk),
                    //.spkclk(spkclk),
                    .rd_data(mac_rd_data[u][c]),
                    .rd_en(mac_rd_en[c]),
                    .rst_acc(mac_rst_acc[c]),
                    //.inspk(mac_inspk[c]),
                    //.outspk(mac_out_spk[u][c]),
                    .activation(mac_activation[u][c])
                );
            end
        end
    endgenerate



    // ─────────────────────────────────────────────────────────────
    // Cross-channel accumulation + bias addition
    // ─────────────────────────────────────────────────────────────
    wire [PRECISION-1:0] xchan_biased [P-1:0][FANOUT-1:0];

    xchan_bias_acc #(
        .P(P),
        .IN_CHANNEL(IN_CHANNEL),
        .FANOUT(FANOUT),
        .INTEGER_PRECISION(INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) xchan_acc_inst (
        .mac_activation(mac_activation),
        .active_bias(active_bias),
        .xchan_biased(xchan_biased)
    );


    // ─────────────────────────────────────────────────────────────
    // Capture registers (latch results at end of each phase)
    // ─────────────────────────────────────────────────────────────
    reg [PRECISION-1:0] captured_activation [OUT_CHANNEL-1:0][FANOUT-1:0];

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            for (int oc = 0; oc < OUT_CHANNEL; oc++)
                for (int fm = 0; fm < FANOUT; fm++)
                    captured_activation[oc][fm] <= '0;
        end else if (capture_en) begin
            for (int uu_i = 0; uu_i < P; uu_i++) begin
                if ((phase_cnt * P + uu_i) < OUT_CHANNEL) begin
                    for (int fm = 0; fm < FANOUT; fm++)
                        captured_activation[phase_cnt * P + uu_i][fm] <= xchan_biased[uu_i][fm];
                end
            end
        end
    end

    // ─────────────────────────────────────────────────────────────
    // Stable snapshot — copies ALL output channels at once on phase_done.
    //   captured_activation is updated incrementally (P channels per phase).
    //   stable_activation holds a complete, consistent snapshot that
    //   the CDC synchronizer can safely sample without seeing partial updates.
    // ─────────────────────────────────────────────────────────────
    reg [PRECISION-1:0] stable_activation [OUT_CHANNEL-1:0][FANOUT-1:0];
 
    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            for (int oc = 0; oc < OUT_CHANNEL; oc++)
                for (int fm = 0; fm < FANOUT; fm++)
                    stable_activation[oc][fm] <= '0;
        end else if (phase_done) begin
            for (int oc = 0; oc < OUT_CHANNEL; oc++)
                for (int fm = 0; fm < FANOUT; fm++)
                    stable_activation[oc][fm] <= captured_activation[oc][fm];
        end
    end


    // // ─────────────────────────────────────────────────────────────
    // // CDC: memclk → spkclk (after all phases are captured)
    // //   captured_activation is stable after phase_done.
    // //   synchronizer2 crosses it into the spkclk domain for
    // //   pooling and LIF neurons.
    // // ─────────────────────────────────────────────────────────────
    // wire [PRECISION-1:0] cdc_activation [OUT_CHANNEL-1:0][FANOUT-1:0];
 
    // genvar cdc_oc;
    // generate
    //     for (cdc_oc = 0; cdc_oc < OUT_CHANNEL; cdc_oc = cdc_oc + 1) begin : cdc_sync
    //         synchronizer2 #(
    //             .N(PRECISION),
    //             .M(FANOUT)
    //         ) cdc_act (
    //             .rst(rst),
    //             .clk(spkclk),
    //             .in(captured_activation[cdc_oc]),
    //             .out(cdc_activation[cdc_oc])
    //         );
    //     end
    // endgenerate


    // ─────────────────────────────────────────────────────────────
    // Pooling
    // ─────────────────────────────────────────────────────────────
    logic [PRECISION-1:0] pooled_activation [OUT_CHANNEL-1:0][POOLED_FANOUT-1:0];

    pooling #(
        .X_FANIN           (X_FANOUT),
        .Y_FANIN           (Y_FANOUT),
        .POOL_X_KERNEL     (POOL_X_KERNEL),
        .POOL_Y_KERNEL     (POOL_Y_KERNEL),
        .POOL_STRIDE       (POOL_STRIDE),
        .OUT_CHANNEL       (OUT_CHANNEL),
        .POOL_MODE         (POOL_MODE),
        .INTEGER_PRECISION (INTEGER_PRECISION),
        .DECIMAL_PRECISION (DECIMAL_PRECISION)
    ) pool_inst (
        .clk            (spkclk),
        .rst            (rst),
        .activation_in  (stable_activation),
        .activation_out (pooled_activation)
    );


    // ─────────────────────────────────────────────────────────────
    // LIF neurons — OUT_CHANNEL × FANOUT (all kept)
    // ─────────────────────────────────────────────────────────────
    genvar q, s;
    generate
        for (q = 0; q < OUT_CHANNEL; q = q + 1) begin : lif_oc
            for (s = 0; s < FANOUT; s = s + 1) begin : lif_f
                lif #(
                    .INTEGER_PRECISION(INTEGER_PRECISION),
                    .DECIMAL_PRECISION(DECIMAL_PRECISION)
                ) lif_inst (
                    .rst(rst | rst_neuron),
                    .clk(spkclk),
                    .vth(vth_local[q]),
                    .decay_rate(decay_rate_local[q]),
                    .grow_rate(grow_rate_local[q]),
                    .vrest(vrest_local[q]),
                    .reset_mechanism(reset_mechanism_local[q]),
                    .refractory_period(refractory_period_local[q]),
                    .activation(pooled_activation[q][s]),
                    .outspk(outspk[q][s]),
                    .vmem(vmem[q][s])
                );
            end
        end
    endgenerate

endmodule
