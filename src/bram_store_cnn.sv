/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2026 Drexel University

// Author       : Sarah Johari (original bmem_cnn), refactored for folding
// Date         : May 2026
// File         : bram_store_cnn.sv
// Desc         : Pure BRAM weight storage, split out from bmem_cnn.
//                Holds one kernel's worth of synaptic weights (MEM_SIZE entries
//                of WT_PRECISION bits each).
//
//                Ports:
//                  Write: wr_en, wr_addr, wr_data  (programming weights)
//                  Read:  rd_addr → rd_data         (1-cycle registered output)
//
//                No MAC, no accumulator, no pipeline registers, no CDC.
//                Those are in mac_unit_cnn.sv.
//
//                Instantiated OUT_CHANNEL × IN_CHANNEL times in cnn_layer_folded
//                (all weights resident in block RAM).
// -----------------------------------------------------------------------------*/
`timescale 1ns / 1ps

`include "defines.vh"

module bram_store_cnn #(
    // configurable parameters
    parameter X_KERNEL             = 2,           // kernel height
    parameter Y_KERNEL             = 3,           // kernel width
    parameter WT_INTEGER_PRECISION = 2,           // integer bits in weight
    parameter DECIMAL_PRECISION    = 4,           // fractional bits

    // local parameters
    localparam MEM_SIZE     = X_KERNEL * Y_KERNEL,
    localparam WT_PRECISION = (1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION),
    localparam ADDR_WIDTH   = $clog2(MEM_SIZE)
)(
    input                           memclk,       // memory clock

    // ── write port (weight programming) ───────────────────
    input                           wr_en,        // write enable
    input  [ADDR_WIDTH-1:0]         wr_addr,      // write address
    input  [WT_PRECISION-1:0]       wr_data,      // weight value

    // ── read port ─────────────────────────────────────────
    input  [ADDR_WIDTH-1:0]         rd_addr,      // read address
    output reg [WT_PRECISION-1:0]   rd_data       // registered read data (1-cycle latency)
);

    // ── block RAM array ───────────────────────────────────
    (* ram_style = "block" *) reg [WT_PRECISION-1:0] mem [MEM_SIZE-1:0];

    // ── synchronous read + write ──
    always @(posedge memclk) begin
        if (wr_en) begin
            mem[wr_addr] <= wr_data;
        end
        rd_data <= mem[rd_addr];
    end

endmodule
