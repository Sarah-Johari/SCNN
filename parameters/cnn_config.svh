/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Sep 9, 2025
// File         : cnn_config.svh
//
// ─── Description ────────────────────────────────────────────────
//
//   Per-layer CNN configuration header. Included via `include
//   inside scnncore's parameter list. Defines kernel geometry,
//   stride, channel counts, and output dimensions for each CNN
//   layer, then packs them into a 2D config array for indexed
//   access.
//
//   All parameters marked //swctrl are software-controllable
//   (overridable at synthesis or from the configuration interface).
//
// ─── Config Array Layout ────────────────────────────────────────
//
//   cnn_config[layer][field]:
//
//     [0] X_KERNEL      Kernel height
//     [1] Y_KERNEL      Kernel width
//     [2] STRIDE        Convolution stride
//     [3] IN_CHANNEL    Number of input channels
//     [4] OUT_CHANNEL   Number of output channels
//     [5] X_FANOUT      Output feature map height
//     [6] Y_FANOUT      Output feature map width
//
// ─── Usage ──────────────────────────────────────────────────────
//
//   In scnncore.sv:
//     module scnncore #(
//         `include "cnn_config.svh"
//         ,
//         ...
//     )
//
//   Then access per-layer values as:
//     .X_KERNEL(cnn_config[0][0])     // layer 0 kernel height
//     .OUT_CHANNEL(cnn_config[1][4])  // layer 1 output channels
//     .X_FANIN(cnn_config[0][5])      // layer 1 input = layer 0 output size
//
// ─── Adding a New Layer ─────────────────────────────────────────
//
//   1. Increment NUM_CNN_LAYERS
//   2. Add parameter block (X_KERNEL_N, Y_KERNEL_N, ...)
//   3. Add row to cnn_config array
//
// -----------------------------------------------------------------------------*/

`ifndef CNN_CONFIG_SVH
`define CNN_CONFIG_SVH

parameter NUM_CNN_LAYERS = 2;	

// layer 0
parameter X_KERNEL_0 = 1;	
parameter Y_KERNEL_0 = 5;	
parameter STRIDE_0   = 2;	
parameter IN_CH_0    = 3;	
parameter OUT_CH_0   = 16;	
parameter X_FANOUT_0 = 1;	
parameter Y_FANOUT_0 = 48;	

// layer 1
parameter X_KERNEL_1 = 1;	
parameter Y_KERNEL_1 = 5;	
parameter STRIDE_1   = 5;
parameter IN_CH_1    = 16;
parameter OUT_CH_1   = 32;	
parameter X_FANOUT_1 = 1;	
parameter Y_FANOUT_1 = 9;	


localparam int cnn_config [0:NUM_CNN_LAYERS-1][0:6] = '{
    '{X_KERNEL_0, Y_KERNEL_0, STRIDE_0, IN_CH_0, OUT_CH_0, X_FANOUT_0, Y_FANOUT_0},   // layer 0
    '{X_KERNEL_1, Y_KERNEL_1, STRIDE_1, IN_CH_1, OUT_CH_1, X_FANOUT_1, Y_FANOUT_1}   // layer 1
};

`endif