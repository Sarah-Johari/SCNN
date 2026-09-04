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
// File     	: cnn_config.svh
// Desc     	: 
// -----------------------------------------------------------------------------*/
// Number of layers
parameter NUM_CNN_LAYERS = 2,	//swctrl
// Each layer has 6 parameters: 
//{x_kernel, y_kernel, stride, in_channel, out_channel, x_fanout, y_fanout, 
//        pool_x_kernel, pool_y_kernel, pool_stride, pool_mode}

//layer0
parameter X_KERNEL_0      = 1,	
parameter Y_KERNEL_0      = 5,	
parameter STRIDE_0        = 2,	
parameter IN_CH_0         = 9,	
parameter OUT_CH_0        = 16,	
parameter X_FANOUT_0      = 1,	
parameter Y_FANOUT_0      = 48,	
parameter POOL_X_KERNEL_0 = 1,		
parameter POOL_Y_KERNEL_0 = 1,		
parameter POOL_STRIDE_0   = 1,		
parameter POOL_MODE_0     = 2,		

//layer1
parameter X_KERNEL_1      = 1,	
parameter Y_KERNEL_1      = 5,	
parameter STRIDE_1        = 5,
parameter IN_CH_1         = 16,	
parameter OUT_CH_1        = 32,	
parameter X_FANOUT_1      = 1,	
parameter Y_FANOUT_1      = 9,	
parameter POOL_X_KERNEL_1 = 1,		
parameter POOL_Y_KERNEL_1 = 1,		
parameter POOL_STRIDE_1   = 1,		
parameter POOL_MODE_1     = 2,		


localparam int cnn_config [0:NUM_CNN_LAYERS-1][0:10] = '{
    '{X_KERNEL_0, Y_KERNEL_0, STRIDE_0, IN_CH_0, OUT_CH_0, X_FANOUT_0, Y_FANOUT_0,
      POOL_X_KERNEL_0, POOL_Y_KERNEL_0, POOL_STRIDE_0, POOL_MODE_0},   // layer 0
      
    '{X_KERNEL_1, Y_KERNEL_1, STRIDE_1, IN_CH_1, OUT_CH_1, X_FANOUT_1, Y_FANOUT_1,
      POOL_X_KERNEL_1, POOL_Y_KERNEL_1, POOL_STRIDE_1, POOL_MODE_1}    // layer 1
}
