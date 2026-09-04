/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Date         : Aug 2026
// File         : cnn_layer_folded_shared.sv
// Desc         : Spiking convolutional layer folded on BOTH channel dimensions.
//
//   Third arm of the comparison:
//     cnn_layer               : nothing folded (baseline)
//     cnn_layer_folded        : output channels folded by P
//     cnn_layer_folded_shared : output channels folded by P
//                               AND input-channel sequencers shared by Q   <-- this
//
//   P = OUTPUT channels computed in parallel  -> P x IN_CHANNEL MAC units
//                                             -> ceil(OUT_CHANNEL/P) phases
//   Q = INPUT-channel sequencers in parallel  -> Q syn_access_cnn instances
//                                             -> ceil(IN_CHANNEL/Q) capture slots
//
//   Both: 1 = maximum sharing, max = no sharing.
//   Q = IN_CHANNEL reproduces cnn_layer_folded's sequencer arrangement.
//
//   Sub-modules:
//     syn_access_cnn          : Read address sequencer   [Q]   <-- SHARED, UNMODIFIED
//     phase_controller_shared : Capture FSM + MAC ctrl    [1]
//     bram_store_cnn          : BRAM weight storage       [OUT_CHANNEL x IN_CHANNEL]
//     bram_rd_mux             : BRAM->MAC data mux        [1]
//     mac_unit_cnn            : MAC datapath              [P x IN_CHANNEL]
//     bias_controller         : Bias storage + phase mux  [1]
//     xchan_bias_acc          : Cross-channel acc + bias  [1]
//     pooling                 : Activation pooling        [1]
//     lif                     : LIF neurons               [OUT_CHANNEL x FANOUT]
//
//   Data flow:
//     PH_CAPTURE : inspk -> [mux by slot_sel] -> syn_access_cnn (Q of them)
//                        -> captured_rd_en register file.   MACs idle.
//     PH_SWEEP   : captured_rd_en -> ALL IN_CHANNEL MAC columns in parallel
//                        -> xchan_bias_acc -> capture regs -> pooling -> lif
//
//   The sequencers are shared; the datapath never is. That is why xchan_bias_acc
//   and the MAC array are unaffected by Q — during replay every input channel
//   still presents simultaneously.
//
//   NOTE: the sa_inspk mux below is a hard contract with phase_controller_shared.
//   It MUST be gated by capture_active. Parking the mux at zero outside
//   PH_CAPTURE is what makes slot 0 trigger the same way every other slot does.
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

`include "defines.vh"

module cnn_layer_folded_shared #(
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
    parameter P                    = 1,   // output channels in parallel
    parameter Q                    = 1,   // input-channel sequencers in parallel

    localparam MEM_SIZE        = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM  = $clog2(MEM_SIZE),
    localparam X_FANOUT        = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT        = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT          = X_FANOUT * Y_FANOUT,
    localparam FANIN           = X_FANIN * Y_FANIN,
    localparam POOLED_X_FANOUT = ((X_FANOUT - POOL_X_KERNEL) / POOL_STRIDE) + 1,
    localparam POOLED_Y_FANOUT = ((Y_FANOUT - POOL_Y_KERNEL) / POOL_STRIDE) + 1,
    localparam POOLED_FANOUT   = POOLED_X_FANOUT * POOLED_Y_FANOUT,
    localparam IN_CH_WIDTH     = (IN_CHANNEL  <= 1) ? 1 : $clog2(IN_CHANNEL),
    localparam OUT_CH_WIDTH    = (OUT_CHANNEL <= 1) ? 1 : $clog2(OUT_CHANNEL),
    localparam WT_PRECISION    = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam PRECISION       = (1 + INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam NUM_PHASES      = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH     = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1,
    // ── input-channel sequencer sharing ──
    localparam NUM_SA          = Q,
    localparam SLOTS           = (IN_CHANNEL + Q - 1) / Q,
    localparam SEL_WIDTH       = (SLOTS > 1) ? $clog2(SLOTS) : 1
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
    // Shared read-address sequencers — Q instances, time-multiplexed
    // over NUM_SLOTS = ceil(IN_CHANNEL/Q) input channels.
    //
    // Instance s during slot j serves input channel (j*Q + s), the same
    // interleaving bram_rd_mux uses for (phase*P + u).
    //
    // syn_access_cnn is instantiated UNMODIFIED. It self-triggers on any
    // change at its inspk port, so switching the mux is what starts each
    // sweep. Parking the mux at '0 outside PH_CAPTURE (via capture_active)
    // makes slot 0 behave exactly like the rest.
    // ─────────────────────────────────────────────────────────────
    wire [SEL_WIDTH-1:0] slot_sel;
    wire                 capture_active;

    wire [FANIN-1:0]  sa_inspk [NUM_SA-1:0];
    wire [FANOUT-1:0] sa_rd_en [NUM_SA-1:0];

    genvar sq;
    generate
        for (sq = 0; sq < NUM_SA; sq = sq + 1) begin : shared_seq

            // channel this instance serves in the current slot
            wire [31:0] ch_idx  = (slot_sel * Q) + sq;
            wire        ch_vld  = (ch_idx < IN_CHANNEL);   // guard: IN_CHANNEL % Q != 0
            wire [31:0] ch_safe = ch_vld ? ch_idx : 32'd0; // keep the index in range

            assign sa_inspk[sq] = (capture_active && ch_vld) ? inspk[ch_safe] : '0;

            syn_access_cnn #(
                .X_FANIN(X_FANIN),
                .Y_FANIN(Y_FANIN),
                .X_KERNEL(X_KERNEL),
                .Y_KERNEL(Y_KERNEL),
                .STRIDE(STRIDE)
            ) rd_addr_decoder (
                .rst(rst),
                .memclk(memclk),
                .inspk(sa_inspk[sq]),
                .rd_en(sa_rd_en[sq])
            );

        end
    endgenerate


    // ─────────────────────────────────────────────────────────────
    // Phase controller (capture FSM + MAC control + BRAM addr)
    // ─────────────────────────────────────────────────────────────
    wire [FANOUT-1:0]         mac_rd_en [IN_CHANNEL-1:0];
    wire                      mac_rst_acc_all;
    wire [ADDR_WIDTH_MEM-1:0] bram_rd_addr;    // scalar: shared by every channel
    wire [PHASE_WIDTH-1:0]    phase_cnt;
    wire                      capture_en;

    phase_controller_shared #(
        .X_FANIN(X_FANIN),
        .Y_FANIN(Y_FANIN),
        .X_KERNEL(X_KERNEL),
        .Y_KERNEL(Y_KERNEL),
        .STRIDE(STRIDE),
        .IN_CHANNEL(IN_CHANNEL),
        .OUT_CHANNEL(OUT_CHANNEL),
        .P(P),
        .Q(Q)
    ) phase_ctrl (
        .rst(rst),
        .memclk(memclk),
        .spkclk(spkclk),
        .sa_rd_en(sa_rd_en),
        .slot_sel(slot_sel),
        .capture_active(capture_active),
        .mac_rd_en(mac_rd_en),
        .mac_rst_acc_all(mac_rst_acc_all),
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
    // Every BRAM reads the same kernel index, so rd_addr is a scalar.
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
                    .rd_addr(bram_rd_addr),
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
    // MAC units — P × IN_CHANNEL
    // rst_acc is a blanket clear at each phase start: with a shared
    // sequencer the per-window mask is unavailable, and it is provably
    // redundant (any window the selective scheme skips is already zero).
    // ─────────────────────────────────────────────────────────────
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
                    .rd_data(mac_rd_data[u][c]),
                    .rd_en(mac_rd_en[c]),
                    .rst_acc({FANOUT{mac_rst_acc_all}}),
                    .activation(mac_activation[u][c])
                );
            end
        end
    endgenerate


    // ─────────────────────────────────────────────────────────────
    // Cross-channel accumulation + bias addition
    // Unaffected by Q — all IN_CHANNEL operands arrive together in replay.
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
    // Capture registers (latch P results at the end of each phase)
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
    // Stable snapshot — copies ALL output channels at once on phase_done,
    // so downstream never sees a partially-updated set.
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
    genvar oc_l, fm_l;
    generate
        for (oc_l = 0; oc_l < OUT_CHANNEL; oc_l = oc_l + 1) begin : lif_oc
            for (fm_l = 0; fm_l < FANOUT; fm_l = fm_l + 1) begin : lif_f
                lif #(
                    .INTEGER_PRECISION(INTEGER_PRECISION),
                    .DECIMAL_PRECISION(DECIMAL_PRECISION)
                ) lif_inst (
                    .rst(rst | rst_neuron),
                    .clk(spkclk),
                    .vth(vth_local[oc_l]),
                    .decay_rate(decay_rate_local[oc_l]),
                    .grow_rate(grow_rate_local[oc_l]),
                    .vrest(vrest_local[oc_l]),
                    .reset_mechanism(reset_mechanism_local[oc_l]),
                    .refractory_period(refractory_period_local[oc_l]),
                    .activation(pooled_activation[oc_l][fm_l]),
                    .outspk(outspk[oc_l][fm_l]),
                    .vmem(vmem[oc_l][fm_l])
                );
            end
        end
    endgenerate

endmodule
