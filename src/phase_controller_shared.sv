/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Date         : Aug 2026
// File         : phase_controller_shared.sv
// Desc         : Phase controller for a CNN layer folded on BOTH channel
//                dimensions (pure-capture model).
//
// ─── THE TWO FOLDING FACTORS ─────────────────────────────────────────────────
//
//   P = number of OUTPUT channels computed in parallel by the MAC array.
//         hardware : P x IN_CHANNEL mac_unit_cnn instances
//         passes   : NUM_PHASES = ceil(OUT_CHANNEL / P)
//
//   Q = number of INPUT-channel address sequencers running in parallel.
//         hardware : Q syn_access_cnn instances
//         passes   : NUM_SLOTS = ceil(IN_CHANNEL / Q)
//
//   Both use the same convention:
//         value = 1    -> maximum resource sharing (slowest, smallest)
//         value = max  -> no sharing at all        (fastest, largest)
//
//   Q = IN_CHANNEL reproduces the original one-sequencer-per-channel design.
//
//   Cycle cost (symmetric in the two knobs):
//         TOTAL = 3 + NUM_SLOTS*SLOT_CYCLES + NUM_PHASES*PHASE_CYCLES + 1
//               = 3 + 9*( ceil(IN_CHANNEL/Q) + ceil(OUT_CHANNEL/P) ) + 1
//                 for MEM_SIZE = 5
//
// ─── WHY PURE CAPTURE ────────────────────────────────────────────────────────
//
//   With Q < IN_CHANNEL only some input channels have a live rd_en at any
//   instant, so the MAC array cannot compute during the sweep. Therefore:
//
//     PH_CAPTURE : walk all NUM_SLOTS slots, filling captured_rd_en. MACs idle.
//     PH_RST_MAC )
//     PH_SWEEP   ) x NUM_PHASES  -- every phase is a replay phase, and ALL
//     PH_FLUSH   )                  IN_CHANNEL MACs fire in parallel here.
//
//   captured_rd_en is written one slot at a time but read all-channels-at-once.
//   That serial-write / parallel-read asymmetry is the whole mechanism: only
//   the sequencers are shared, never the datapath.
//
// ─── syn_access_cnn IS USED COMPLETELY UNMODIFIED ────────────────────────────
//
//   It is self-triggering: when the parent's mux presents different data, the
//   module sees it as a spike event (q2^q3 != 0), fires rst_acc, and runs its
//   own sweep. We never drive it -- we change its input and catch rd_en.
//
//   PARENT CONTRACT -- the mux MUST be gated by capture_active:
//
//       assign sa_inspk[s] = (capture_active &&
//                             ((slot_sel*Q + s) < IN_CHANNEL))
//                            ? inspk[slot_sel*Q + s] : '0;
//
//   Parking the mux at zero outside PH_CAPTURE is what makes slot 0 behave
//   like every other slot: entering PH_CAPTURE is itself the input transition
//   that triggers the sequencers. Without parking, slot 0's sweep is driven by
//   the external spike edge and starts before the FSM is in state.
//
//   Per-slot timing (mux switches at slot_cnt = 0):
//
//     slot_cnt : 0   mux presents this slot's channels
//                1   inspk_q1 <= data
//                2   inspk_q2 <= q1   -> rst_acc fires inside syn_access_cnn
//                3   inspk_q3 <= q2, FSM STREAMING, k=0  -> rd_en VALID
//                4   k=1  |
//                5   k=2  |  captured on the following clock edge,
//                6   k=3  |  into captured_rd_en[ch][slot_cnt - CAP_START]
//                7   k=4  |
//                8   syn_access_cnn FSM -> DONE (returns to IDLE)
//               ---  wrap: slot_sel++, next slot
//
//   CAP_START = 3 is the one number here derived by reading syn_access_cnn
//   rather than observing it. CONFIRM IT ON A WAVEFORM before trusting results.
//
// ─── ACCUMULATOR CLEARING ────────────────────────────────────────────────────
//
//   rst_acc from a shared sequencer is meaningless per-channel (it diffs one
//   channel against the previously muxed one, not against the previous
//   timestep), so it is not used at all. psum is cleared by a blanket pulse at
//   each phase start (mac_rst_acc_all). This is functionally identical to the
//   original selective clear: any window the selective scheme leaves uncleared
//   is provably already zero, because the timestep at which its spikes
//   disappeared would have had or_acc = 1 and cleared it then.
//
//   Event trigger comes from spkclk, NOT from sa_rst_acc: with a shared
//   sequencer only some channels are visible at a time, so an sa_rst_acc-based
//   trigger would miss an event in which the visible channels happen to be
//   quiet.
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

module phase_controller_shared #(
    parameter X_FANIN          = 4,
    parameter Y_FANIN          = 5,
    parameter X_KERNEL         = 2,
    parameter Y_KERNEL         = 3,
    parameter STRIDE           = 1,
    parameter IN_CHANNEL       = 1,
    parameter OUT_CHANNEL      = 1,
    parameter P                = 1,   // output channels computed in parallel
    parameter Q                = 1,   // input-channel sequencers in parallel

    localparam X_FANOUT        = ((X_FANIN - X_KERNEL) / STRIDE) + 1,
    localparam Y_FANOUT        = ((Y_FANIN - Y_KERNEL) / STRIDE) + 1,
    localparam FANOUT          = X_FANOUT * Y_FANOUT,
    localparam FANIN           = X_FANIN * Y_FANIN,
    localparam MEM_SIZE        = X_KERNEL * Y_KERNEL,
    localparam ADDR_WIDTH_MEM  = $clog2(MEM_SIZE),

    // ── output-channel folding ──
    localparam NUM_PHASES      = (OUT_CHANNEL + P - 1) / P,
    localparam PHASE_WIDTH     = (NUM_PHASES > 1) ? $clog2(NUM_PHASES) : 1,
    localparam PHASE_CYCLES    = MEM_SIZE + 4,   // RST_MAC(1) + SWEEP(MEM_SIZE) + FLUSH(3)

    // ── input-channel sequencer sharing ──
    localparam NUM_SA          = Q,                              // Q IS the instance count
    localparam NUM_SLOTS       = (IN_CHANNEL + Q - 1) / Q,       // channels per instance
    localparam SEL_WIDTH       = (NUM_SLOTS > 1) ? $clog2(SLOTS) : 1,
    localparam SLOT_CYCLES     = MEM_SIZE + 4,   // 3 propagate + MEM_SIZE sweep + 1 return
    localparam SLOT_WIDTH      = $clog2(SLOT_CYCLES),
    localparam CAP_START       = 3,              // slot_cnt at which rd_en(k=0) is valid

    localparam TRIG_LATENCY    = 3,              // spkclk edge -> PH_CAPTURE entry
    localparam TOTAL_CYCLES    = TRIG_LATENCY
                               + (NUM_SLOTS  * SLOT_CYCLES)
                               + (NUM_PHASES * PHASE_CYCLES)
                               + 1
)(
    input                          rst,
    input                          memclk,
    input                          spkclk,        // event trigger source

    // ── from the Q shared syn_access_cnn instances ──
    input  [FANOUT-1:0]            sa_rd_en [NUM_SA-1:0],

    // ── to the parent's inspk mux (see PARENT CONTRACT above) ──
    output reg [SEL_WIDTH-1:0]     slot_sel,
    output                         capture_active,

    // ── to the MAC array ──
    output reg [FANOUT-1:0]        mac_rd_en [IN_CHANNEL-1:0],
    output                         mac_rst_acc_all,

    // ── to the BRAM array (scalar: every channel reads the same kernel index) ──
    output [ADDR_WIDTH_MEM-1:0]    bram_rd_addr,

    // ── to the parent ──
    output [PHASE_WIDTH-1:0]       phase_cnt_out,
    output                         capture_en,
    output                         phase_done
);



    // ═════════════════════════════════════════════════════════════
    // 1. Event trigger — rising edge of spkclk, sampled into memclk.
    //    Two stages settle the crossing, the third makes the edge.
    // ═════════════════════════════════════════════════════════════
    reg spk_s1, spk_s2, spk_s3;

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            spk_s1 <= 1'b0;
            spk_s2 <= 1'b0;
            spk_s3 <= 1'b0;
        end else begin
            spk_s1 <= spkclk;
            spk_s2 <= spk_s1;
            spk_s3 <= spk_s2;
        end
    end

    wire event_start = spk_s2 & ~spk_s3;


    // ═════════════════════════════════════════════════════════════
    // 2. Phase FSM
    // ═════════════════════════════════════════════════════════════
    typedef enum logic [2:0] {
        PH_IDLE,
        PH_CAPTURE,
        PH_RST_MAC,
        PH_SWEEP,
        PH_FLUSH,
        PH_DONE
    } phase_state_t;

    phase_state_t            ph_state;
    reg [PHASE_WIDTH-1:0]    phase_cnt;
    reg [ADDR_WIDTH_MEM-1:0] loc_k;
    reg [1:0]                flush_cnt;
    reg [SLOT_WIDTH-1:0]     slot_cnt;

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            ph_state  <= PH_IDLE;
            phase_cnt <= '0;
            loc_k     <= '0;
            flush_cnt <= '0;
            slot_cnt  <= '0;
            slot_sel  <= '0;
        end else begin
            case (ph_state)

                // ── Parked. Counters re-armed every cycle. Mux is held at
                //    zero via capture_active, so the sequencers see nothing.
                PH_IDLE: begin
                    phase_cnt <= '0;
                    loc_k     <= '0;
                    slot_cnt  <= '0;
                    slot_sel  <= '0;
                    if (event_start)
                        ph_state <= PH_CAPTURE;
                end

                // ── Capture pass: NUM_SLOTS slots of SLOT_CYCLES each.
                //    MACs are idle; only captured_rd_en is written.
                PH_CAPTURE: begin
                    if (slot_cnt == SLOT_CYCLES - 1) begin
                        slot_cnt <= '0;
                        if (slot_sel == NUM_SLOTS - 1) begin
                            slot_sel  <= '0;
                            phase_cnt <= '0;
                            ph_state  <= PH_RST_MAC;   // begin replay phase 0
                        end else begin
                            slot_sel <= slot_sel + 1'b1;   // advance the inspk mux
                        end
                    end else begin
                        slot_cnt <= slot_cnt + 1'b1;
                    end
                end

                // ── Replay phase: blanket-clear the accumulators
                PH_RST_MAC: begin
                    loc_k    <= '0;
                    ph_state <= PH_SWEEP;
                end

                // ── Replay phase: sweep kernel positions, all channels parallel
                PH_SWEEP: begin
                    if (loc_k == MEM_SIZE - 1) begin
                        loc_k     <= '0;
                        flush_cnt <= '0;
                        ph_state  <= PH_FLUSH;
                    end else begin
                        loc_k <= loc_k + 1'b1;
                    end
                end

                // ── Replay phase: drain BRAM + MAC pipeline, then latch
                PH_FLUSH: begin
                    if (flush_cnt == 2'd2) begin
                        if (phase_cnt == NUM_PHASES - 1)
                            ph_state <= PH_DONE;
                        else begin
                            phase_cnt <= phase_cnt + 1'b1;
                            ph_state  <= PH_RST_MAC;
                        end
                    end else begin
                        flush_cnt <= flush_cnt + 1'b1;
                    end
                end

                PH_DONE: begin
                    ph_state <= PH_IDLE;
                end

                default: ph_state <= PH_IDLE;

            endcase
        end
    end


    // ═════════════════════════════════════════════════════════════
    // 3. rd_en capture register file
    //
    //    Written one slot at a time during PH_CAPTURE; read all channels at
    //    once during PH_SWEEP. Timing is fixed by slot_cnt (see CAP_START),
    //    not by sa_rst_acc — so a slot whose channels happen to carry the same
    //    data as the previous slot still writes (zeros included) rather than
    //    silently leaving last timestep's values in place.
    // ═════════════════════════════════════════════════════════════
    reg [FANOUT-1:0] captured_rd_en [IN_CHANNEL-1:0][MEM_SIZE-1:0];

    always @(posedge memclk or posedge rst) begin
        if (rst) begin
            for (int ch = 0; ch < IN_CHANNEL; ch++)
                for (int k = 0; k < MEM_SIZE; k++)
                    captured_rd_en[ch][k] <= '0;
        end else if ((ph_state == PH_CAPTURE) &&
                     (slot_cnt >= CAP_START) &&
                     (slot_cnt <  CAP_START + MEM_SIZE)) begin
            for (int s = 0; s < NUM_SA; s++) begin
                // guard for IN_CHANNEL not divisible by Q
                if ((slot_sel * Q + s) < IN_CHANNEL)
                    captured_rd_en[slot_sel * Q + s][slot_cnt - CAP_START] <= sa_rd_en[s];
            end
        end
    end


    // ═════════════════════════════════════════════════════════════
    // 4. MAC control
    //    rd_en:   replayed from the capture file during PH_SWEEP only. All
    //             IN_CHANNEL channels fire in parallel — the serialization
    //             existed only during PH_CAPTURE.
    //    rst_acc: blanket clear at each phase start.
    // ═════════════════════════════════════════════════════════════
    always_comb begin
        for (int ch = 0; ch < IN_CHANNEL; ch++)
            mac_rd_en[ch] = '0;

        if (ph_state == PH_SWEEP)
            for (int ch = 0; ch < IN_CHANNEL; ch++)
                mac_rd_en[ch] = captured_rd_en[ch][loc_k];
    end

    assign mac_rst_acc_all = (ph_state == PH_RST_MAC);


    // ═════════════════════════════════════════════════════════════
    // 5. Remaining outputs
    // ═════════════════════════════════════════════════════════════
    assign capture_active = (ph_state == PH_CAPTURE);
    assign bram_rd_addr   = loc_k;
    assign phase_cnt_out  = phase_cnt;
    assign phase_done     = (ph_state == PH_DONE);
    assign capture_en     = (ph_state == PH_FLUSH) && (flush_cnt == 2'd2);


endmodule
