/* -----------------------------------------------------------------------------
MIT License

Copyright (c) 2023 Drexel Distributed, Intelligent, and Scalable COmputing (DISCO) Lab

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
// Author   	: Sarah Johari
// Email    	: sj984@drexel.edu
// Date     	: Sep 9, 2025
// File     	: parameters.vh
// Desc     	: 
// -----------------------------------------------------------------------------*/
//parameter string INSTALL_DIR  = "C:/vivado_sim/Folded_CNN",        //base installation directory
//neuron configuration
parameter VTH                  = 16,	
parameter DECAY_RATE           = 3,	
parameter GROW_RATE            = 16,	
parameter VREST                = 0,	
parameter RESET_MECHANISM      = 1,	
parameter REFRACTORY_PERIOD    = 0,	
//design parameters
parameter CLK_BFR              = 7,

//hardware parameters
parameter INTEGER_PRECISION    = 5,	
parameter DECIMAL_PRECISION    = 6,	
parameter PRECISION            = (1+INTEGER_PRECISION+DECIMAL_PRECISION),
parameter WT_INTEGER_PRECISION = 1,
parameter WT_PRECISION         = 1 + WT_INTEGER_PRECISION + DECIMAL_PRECISION,

// parameter LAYER_ADDR_START  = 0,
parameter LAYER_ENC_BITS       = 4,	
parameter IN_CHENNEL_ENC_BITS  = 8,	
parameter OUT_CHENNEL_ENC_BITS = 8,
parameter NEURON_ENC_BITS      = 16,
parameter FANIN_ENC_BITS       = 12,	
parameter ADDR_WIDTH           = (LAYER_ENC_BITS + NEURON_ENC_BITS + FANIN_ENC_BITS),
parameter LAYER_ADDR_START     = ( OUT_CHENNEL_ENC_BITS + IN_CHENNEL_ENC_BITS + FANIN_ENC_BITS),
parameter OUT_CH_ADDR_START    = IN_CHENNEL_ENC_BITS + FANIN_ENC_BITS,
parameter IN_CH_ADDR_START     = FANIN_ENC_BITS,
parameter HIDDEN_LAYERS        = 3,
parameter HARDWARE_LAYERS      = (HIDDEN_LAYERS + 1),
parameter LAYER_WIDTH          = $clog2(HARDWARE_LAYERS),

parameter DATA_WIDTH = 32, 				

//gpout/configuration parameters
parameter NEURON_CFG_REG      = 6,
parameter X_FANIN             = 1,	
parameter Y_FANIN             = 100,	
parameter FANIN               = X_FANIN * Y_FANIN,
parameter FANOUT              = 3,	
parameter OUTPUT_NEURONS      = 3,	

parameter WTS_CNT             = 21425,	
parameter CONFIG_REG          = 6,
parameter MAX_NEURON          = 288,
parameter SIM_CNT             = 7450,//     7450, 11170,9310
parameter NUM_STEP            = 50,
parameter PAD_SAMPLES         = 10,
parameter MEM_CLK_PERIOD      = 1,					
parameter SPK_CLK_PERIOD      = (MEM_CLK_PERIOD*MAX_NEURON)+CLK_BFR,	
parameter PRG_CLK_PERIOD      = (2*MEM_CLK_PERIOD),			
parameter DELAY		          = 100,				
parameter EXTRA_CYCLES	      = 10,			
//dummy parameter to mark the end of file
parameter DUMMY_PARAMETER	  = 1					
