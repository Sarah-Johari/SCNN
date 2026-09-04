/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : 2025
// File         : parameters.vh
//
// ─── Description ────────────────────────────────────────────────
//
//   System-level parameter header for the SCNN accelerator.
//   Included via `include inside scnncore and testbench parameter
//   lists. Defines neuron configuration, precision settings,
//   address encoding, clock timing, and simulation constants.
//
//   Parameters marked //swctrl are software-controllable
//   (overridable from the host configuration interface).
//
// ─── Parameter Groups ───────────────────────────────────────────
//
//   1. Installation
//      INSTALL_DIR           Base directory for weight/config files
//
//   2. Neuron Configuration (loaded into decoder_neuron_config)
//      VTH                   Threshold voltage (fixed-point integer)
//      DECAY_RATE            Membrane decay rate
//      GROW_RATE             Activation growth rate
//      VREST                 Resting potential
//      RESET_MECHANISM       Reset mode (0–3, see lif.v)
//      REFRACTORY_PERIOD     Post-spike refractory counter
//
//   3. Precision
//      INTEGER_PRECISION     Integer bits in state variable Qn.m
//      DECIMAL_PRECISION     Fractional bits in Qn.m
//      PRECISION             Total state bits (1 + INT + DEC)
//      WT_INTEGER_PRECISION  Integer bits in weight Qn.m
//      WT_PRECISION          Total weight bits (1 + WT_INT + DEC)
//
//   4. Address Encoding
//      Layout of wr_addr bitfields (MSB → LSB):
//        [LAYER | OUT_CHANNEL | IN_CHANNEL | FANIN]
//
//      LAYER_ENC_BITS        Bits for layer index
//      OUT_CHENNEL_ENC_BITS  Bits for output channel index
//      IN_CHENNEL_ENC_BITS   Bits for input channel index
//      FANIN_ENC_BITS        Bits for synapse address within a neuron
//      NEURON_ENC_BITS       Bits for neuron index (FC layers)
//      ADDR_WIDTH            Total address width
//      LAYER_ADDR_START      Bit position where layer field begins
//      OUT_CH_ADDR_START     Bit position where output channel begins
//      IN_CH_ADDR_START      Bit position where input channel begins
//
//   5. Network Architecture
//      HIDDEN_LAYERS         Number of hidden layers (CNN + FC)
//      HARDWARE_LAYERS       Total layers including output
//      X_FANIN / Y_FANIN     Input feature map dimensions
//      FANIN                 Total input spatial positions
//      FANOUT                Number of output neurons (final layer)
//      MAX_NEURON            Largest FANIN across all FC layers
//                            (sets the memclk-to-spkclk ratio)
//
//   6. Clock Timing
//      CLK_BFR               Extra memclk cycles per spkclk period
//      MEM_CLK_PERIOD         Memory clock period (ns)
//      SPK_CLK_PERIOD         Spike clock period (= MAX_NEURON + CLK_BFR)
//      PRG_CLK_PERIOD         Programming clock period
//
//   7. Simulation
//      WTS_CNT               Total number of weights to program
//      CONFIG_REG             Number of neuron config registers
//      SIM_CNT                Simulation sample count
//      NUM_STEP               Spike timesteps per sample
//      PAD_SAMPLES            Padding samples between inputs
//      DELAY                  Initial delay before simulation starts
//      EXTRA_CYCLES           Extra cycles after last sample
//
// ─── Clock Relationship ─────────────────────────────────────────
//
//   SPK_CLK_PERIOD = MAX_NEURON × MEM_CLK_PERIOD + CLK_BFR
//
//   memclk must complete MAX_NEURON serial MAC cycles (one per
//   pre-synaptic connection in the largest FC layer) plus CLK_BFR
//   overhead cycles within one spkclk period. This ratio also
//   determines the timing budget for the folded CNN layers.
//
// -----------------------------------------------------------------------------*/
`ifndef PARAMETERS_SVH      
`define PARAMETERS_SVH      

parameter string INSTALL_DIR  = "C:/vivado_sim/SpiCA";        //base installation directory

parameter VTH               = 16;	
parameter DECAY_RATE        = 3;	
parameter GROW_RATE         = 16;	
parameter VREST             = 0;	
parameter RESET_MECHANISM   = 1;	
parameter REFRACTORY_PERIOD = 0;	
parameter CLK_BFR           = 7;


parameter INTEGER_PRECISION    = 3;	
parameter DECIMAL_PRECISION    = 4;	
parameter PRECISION            = (1+INTEGER_PRECISION+DECIMAL_PRECISION);
parameter WT_INTEGER_PRECISION = 1;
parameter WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION;


parameter LAYER_ENC_BITS       = 4;	
parameter IN_CHENNEL_ENC_BITS  = 8;	
parameter OUT_CHENNEL_ENC_BITS = 8;	
parameter NEURON_ENC_BITS      = 16;
parameter FANIN_ENC_BITS       = 12;	
parameter ADDR_WIDTH           = (LAYER_ENC_BITS + NEURON_ENC_BITS + FANIN_ENC_BITS);
parameter LAYER_ADDR_START     = ( OUT_CHENNEL_ENC_BITS + IN_CHENNEL_ENC_BITS + FANIN_ENC_BITS);
parameter OUT_CH_ADDR_START    = IN_CHENNEL_ENC_BITS + FANIN_ENC_BITS;
parameter IN_CH_ADDR_START     = FANIN_ENC_BITS;
parameter HIDDEN_LAYERS        = 3;
parameter HARDWARE_LAYERS      = (HIDDEN_LAYERS + 1);
parameter LAYER_WIDTH          = $clog2(HARDWARE_LAYERS);
parameter DATA_WIDTH           = 32; 				


parameter NEURON_CFG_REG      = 6;
parameter X_FANIN             = 1;	
parameter Y_FANIN             = 100;	
parameter FANIN               = X_FANIN * Y_FANIN;
parameter FANOUT              = 3;	

parameter WTS_CNT            = 21425;	
parameter CONFIG_REG         = 6;
parameter MAX_NEURON         = 288;	
parameter SIM_CNT            = 7450;               //    7450, 11170,9310
parameter NUM_STEP           = 50;
parameter PAD_SAMPLES        = 10;
parameter MEM_CLK_PERIOD     = 1;					
parameter SPK_CLK_PERIOD     = (MEM_CLK_PERIOD*MAX_NEURON)+CLK_BFR;	
parameter PRG_CLK_PERIOD     = (2*MEM_CLK_PERIOD);			
parameter DELAY		         = 100;				
parameter EXTRA_CYCLES	     = 10;			

`endif  				
