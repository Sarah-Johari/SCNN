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

module bram_rd_mux_tb;

    // ── parameters ──
    localparam OUT_CHANNEL          = 8;
    localparam IN_CHANNEL           = 4;
    localparam P                    = 4;
    localparam WT_INTEGER_PRECISION = 3;
    localparam DECIMAL_PRECISION    = 4;
    localparam WT_PRECISION = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION);
    localparam NUM_PHASES           = (OUT_CHANNEL + P - 1) / P;
    localparam PHASE_WIDTH          = $clog2(NUM_PHASES);
    

    // ── DUT signals ──
    reg  [PHASE_WIDTH-1:0]     phase_cnt;
    reg  [WT_PRECISION-1:0]    bram_rd_data [OUT_CHANNEL-1:0][IN_CHANNEL-1:0];
    wire [WT_PRECISION-1:0]    mac_rd_data [P-1:0][IN_CHANNEL-1:0];

    // Instantiate DUT
    bram_rd_mux #(
        .OUT_CHANNEL(OUT_CHANNEL),
        .IN_CHANNEL(IN_CHANNEL),
        .P(P),
        .WT_INTEGER_PRECISION(WT_INTEGER_PRECISION),
        .DECIMAL_PRECISION(DECIMAL_PRECISION)
    ) dut (
        .phase_cnt(phase_cnt),
        .bram_rd_data(bram_rd_data),
        .mac_rd_data(mac_rd_data)
    );


    // main
    initial begin
         
    // Fill bram_rd_data with distinct values: bram_rd_data[oc][ic] = oc*10 + ic
        for (int oc = 0; oc < OUT_CHANNEL; oc++) begin
            for (int ic = 0; ic < IN_CHANNEL; ic++) begin
                bram_rd_data[oc][ic] = oc * 10 + ic;
            end
        end 

    phase_cnt = 0;
    #1;

    phase_cnt = 1;
    #1;

    end 

endmodule