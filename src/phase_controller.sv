/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author       : Sarah Johari (original cnn_layer), refactored for folding
// Date         : May 2026
// File         : phase_controller.sv
// Desc         : Phase controller for output-channel-folded CNN layer.
//
//   Capture-and-replay architecture:
//     During phase 0, syn_access_cnn runs its natural kernel sweep.
//     This controller CAPTURES syn_access_cnn's rd_en output at each
//     kernel position into a register file. For phases 1+, it REPLAYS
//     the captured rd_en instead of recomputing it.
//
//   Sweep detection:
//     Instead of duplicating syn_access_cnn's spike delay chain, we
//     watch sa_rst_acc — syn_access_cnn's own output that fires when
//     it detects a spike change. We OR across ALL input channels so
//     we never miss a change on any channel.
//
//   FSM states:
//     PH_IDLE → PH_WAIT_SA → [PH_RST_MAC → PH_SWEEP → PH_FLUSH]* → PH_DONE
//
//   Cycle-by-cycle timing (example: MEM_SIZE=6, SA_SWEEP_CYCLES=9):
//
//     Posedge T:   Both FSMs transition on the same posedge.
//                  syn_access: k=0, state=STREAMING.
//                  phase_ctrl: sa_wait_cnt=0, ph_state=PH_WAIT_SA.
//
//     Posedge T+1: sa_rd_en reflects k=0.
//                  We capture: captured_rd_en[ch][0] ← sa_rd_en[ch]
//                  Then: k becomes 1, sa_wait_cnt becomes 1.
//
//     Posedge T+2: sa_rd_en reflects k=1.
//                  We capture: captured_rd_en[ch][1] ← sa_rd_en[ch]
//                  Then: k becomes 2, sa_wait_cnt becomes 2.
//
//     ...
//
//     Posedge T+6: sa_rd_en reflects k=5 (last kernel position).
//                  We capture: captured_rd_en[ch][5] ← sa_rd_en[ch]
//                  Then: k becomes 0 (DONE), sa_wait_cnt becomes 6
//                  (≥ MEM_SIZE, stop capturing).
//
//     Posedge T+7: sa_wait_cnt=6. Pipeline flush cycle 1.
//     Posedge T+8: sa_wait_cnt=7. Pipeline flush cycle 2.
//     Posedge T+9: sa_wait_cnt=8 = SA_SWEEP_CYCLES-1. Phase 0 ends.
//                  capture_en fires → parent latches results.
//                  If NUM_PHASES > 1: phase_cnt increments, go to PH_RST_MAC.
//                  Phases 1+ replay captured_rd_en[ch][loc_k] with the same
//                  timing: PH_RST_MAC(1) → PH_SWEEP(MEM_SIZE) → PH_FLUSH(3).
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module phase_controller #(
    parameter X_FANIN          = 4,
    parameter Y_FANIN          = 5,
    parameter X_KERNEL         = 2,
    parameter Y_KERNEL         = 3,
    parameter STRIDE           = 1,
    parameter IN_CHANNEL       = 1,
    parameter OUT_CHANNEL      = 1,
    parameter P                = 4,

    localparam X_FANOUT        = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT        = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT          = X_FANOUT * Y_FANOUT,
    localparam FANIN           = X_FANIN * Y_FANIN,
    localparam MEM_SIZE        = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM  = $clog2(MEM_SIZE),
    localparam NUM_PHASES      = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH     = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1,
    localparam SA_SWEEP_CYCLES = MEM_SIZE + 3
)(
    input                          rst,
    input                          memclk,

    // ── syn_access_cnn signals (one per input channel) ──
    input  [FANOUT-1:0]           sa_rd_en   [IN_CHANNEL-1:0],
    input  [FANOUT-1:0]           sa_rst_acc [IN_CHANNEL-1:0],
    input  [FANOUT-1:0]           sa_outspk  [IN_CHANNEL-1:0],
    input  [ADDR_WIDTH_MEM-1:0]   sa_rd_addr [IN_CHANNEL-1:0],

    // ── outputs to MAC units ──
    output reg [FANOUT-1:0]       mac_rd_en  [IN_CHANNEL-1:0],
    output reg [FANOUT-1:0]       mac_rst_acc[IN_CHANNEL-1:0],
    output reg [FANOUT-1:0]       mac_inspk  [IN_CHANNEL-1:0],

    // ── outputs to BRAM array ──
    output [ADDR_WIDTH_MEM-1:0]    bram_rd_addr [IN_CHANNEL-1:0],

    // ── outputs to parent ──
    output [PHASE_WIDTH-1:0]       phase_cnt_out,
    output                          capture_en,
    output reg                      phase_done
);


    // ═════════════════════════════════════════════════════════════
    // 1. Sweep detection — watch sa_rst_acc from ALL channels
    // ═════════════════════════════════════════════════════════════
    reg [IN_CHANNEL-1:0] rst_acc_any;
    always_comb begin
        for (int ch = 0; ch < IN_CHANNEL; ch++)
            rst_acc_any[ch] = |sa_rst_acc[ch];
    end

    wire any_sweep_starting = |rst_acc_any;


    // ═════════════════════════════════════════════════════════════
    // 2. Phase FSM
    // ═════════════════════════════════════════════════════════════
    typedef enum logic [2:0] {
        PH_IDLE,
        PH_WAIT_SA,
        PH_RST_MAC,
        PH_SWEEP,
        PH_FLUSH,
        PH_DONE
    } phase_state_t;

    phase_state_t           ph_state;
    reg [PHASE_WIDTH-1:0]   phase_cnt;
    reg [ADDR_WIDTH_MEM-1:0] loc_k;
    reg [1:0]               flush_cnt;
    reg                     phase_done_r;
    reg                     mac_phase_rst;
    reg [$clog2(SA_SWEEP_CYCLES+1)-1:0] sa_wait_cnt;

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            ph_state      <= PH_IDLE;
            phase_cnt     <= '0;
            loc_k         <= '0;
            flush_cnt     <= '0;
            phase_done_r  <= 1'b0;
//            mac_phase_rst <= 1'b0;
            sa_wait_cnt   <= '0;
        end else begin
            phase_done_r  <= 1'b0;
//            mac_phase_rst <= 1'b0;

            case (ph_state)
                PH_IDLE: begin
                    phase_cnt   <= '0;
                    loc_k       <= '0;
                    sa_wait_cnt <= '0;
                    if (any_sweep_starting)
                        ph_state <= PH_WAIT_SA;
                end

                PH_WAIT_SA: begin  // Phase 0
                    sa_wait_cnt <= sa_wait_cnt + 1;
                    if (sa_wait_cnt == SA_SWEEP_CYCLES - 1) begin
                        if (NUM_PHASES == 1)
                            ph_state <= PH_DONE;
                        else begin
                            phase_cnt <= phase_cnt + 1;
                            ph_state  <= PH_RST_MAC;
                        end
                    end
                end

                PH_RST_MAC: begin
                    // mac_phase_rst <= 1'b1;
                    loc_k         <= '0;
                    ph_state      <= PH_SWEEP;
                end

                PH_SWEEP: begin
                    if (loc_k == MEM_SIZE - 1) begin
                        loc_k     <= '0;
                        flush_cnt <= '0;
                        ph_state  <= PH_FLUSH;
                    end else begin
                        loc_k <= loc_k + 1;
                    end
                end

                PH_FLUSH: begin
                    if (flush_cnt == 2'd2) begin
                        if (phase_cnt == NUM_PHASES - 1)
                            ph_state <= PH_DONE;
                        else begin
                            phase_cnt <= phase_cnt + 1;
                            ph_state  <= PH_RST_MAC;
                        end
                    end else begin
                        flush_cnt <= flush_cnt + 1;
                    end
                end

                PH_DONE: begin
                    // phase_done_r <= 1'b1;
                    ph_state     <= PH_IDLE;
                end
            endcase
        end
    end

    always_comb begin
        mac_phase_rst = (ph_state == PH_RST_MAC)? 1 : 0;
        phase_done    = (ph_state == PH_DONE);
    end

    // assign phase_done    = phase_done_r;
    assign phase_cnt_out = phase_cnt;

    assign capture_en = (ph_state == PH_FLUSH && flush_cnt == 2'd2) ||
                        (ph_state == PH_WAIT_SA && sa_wait_cnt == SA_SWEEP_CYCLES - 1);


    // ═════════════════════════════════════════════════════════════
    // 3. rd_en capture register file
    //    Captures sa_rd_en during phase 0, replays during phases 1+.
    //    sa_wait_cnt aligns with syn_access_cnn's k counter because
    //    both FSMs trigger off the same rst_acc event.
    // ═════════════════════════════════════════════════════════════
    reg [FANOUT-1:0] captured_rd_en [IN_CHANNEL-1:0][MEM_SIZE-1:0];

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            for (int ch = 0; ch < IN_CHANNEL; ch++)
                for (int k = 0; k < MEM_SIZE; k++)
                    captured_rd_en[ch][k] <= '0;
        end else if (ph_state == PH_WAIT_SA && sa_wait_cnt < MEM_SIZE) begin
            for (int ch = 0; ch < IN_CHANNEL; ch++)
                captured_rd_en[ch][sa_wait_cnt] <= sa_rd_en[ch];
        end
    end

    // rst_acc capture: single snapshot per channel
    reg [FANOUT-1:0] captured_rst_acc [IN_CHANNEL-1:0];

    always@(posedge memclk or posedge rst) begin
        if (rst) begin
            for (int ch = 0 ; ch < IN_CHANNEL ; ch++) begin
                captured_rst_acc [ch] <= '0;
            end 
        end else if (ph_state == PH_IDLE && any_sweep_starting) begin
            for (int ch = 0; ch < IN_CHANNEL; ch++)
                captured_rst_acc[ch] <= sa_rst_acc[ch];
        end 
    end

    // ═════════════════════════════════════════════════════════════
    // 4. BRAM read address mux
    //    Phase 0: sa_rd_addr from syn_access_cnn
    //    Phases 1+: loc_k from local kernel counter
    // ═════════════════════════════════════════════════════════════
    genvar a;
    generate
        for (a = 0; a < IN_CHANNEL; a = a + 1) begin : addr_mux
            assign bram_rd_addr[a] = (ph_state == PH_WAIT_SA || ph_state == PH_IDLE) ?
                                      sa_rd_addr[a] : loc_k;
        end
    endgenerate


    // ═════════════════════════════════════════════════════════════
    // 5. MAC control signal mux
    //    rd_en:   phase 0 → live sa_rd_en
    //             phases 1+ → captured_rd_en[ch][loc_k]
    //    rst_acc: phase 0 → sa_rst_acc
    //             PH_RST_MAC → captured_rst_acc[ch]
    //    inspk:   always sa_outspk (stable across all phases)
    // ═════════════════════════════════════════════════════════════

    // Replay rd_en from capture register file
    reg [FANOUT-1:0] replay_rd_en [IN_CHANNEL-1:0];
    always_comb begin
        for (int ch = 0; ch < IN_CHANNEL; ch++)
            replay_rd_en[ch] = captured_rd_en[ch][loc_k];
    end

    // Mux outputs
    always_comb begin
        // Defaults — all outputs zero when not actively driven
        for (int ch = 0; ch < IN_CHANNEL; ch++) begin
            mac_rd_en[ch]  = '0;
            mac_rst_acc[ch]= '0;
            mac_inspk[ch]  = '0;
        end
 
         // Override based on state
        for (int ch = 0; ch < IN_CHANNEL; ch++) begin
            mac_inspk[ch] = sa_outspk[ch];
 
            if (ph_state == PH_WAIT_SA) begin
                mac_rd_en[ch] = sa_rd_en[ch];
            end else begin
                mac_rd_en[ch] = replay_rd_en[ch];
            end
 
            if (ph_state == PH_IDLE) begin
                mac_rst_acc[ch] = sa_rst_acc[ch];
            end else if (ph_state == PH_RST_MAC) begin
                mac_rst_acc[ch] = captured_rst_acc[ch];
            end
        end
    end


endmodule