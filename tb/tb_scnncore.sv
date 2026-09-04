/* -----------------------------------------------------------------------------
SPDX-License-Identifier: MIT
Copyright (c) 2023-2026 Drexel University

// Author       : Sarah Johari
// Email        : sj984@drexel.edu
// Date         : Sep 2025
// File         : tb_scnncore.sv
//
// ─── Description ────────────────────────────────────────────────
//
//   System-level testbench for the SCNN accelerator core.
//   Performs a complete inference run:
//     1. Program neuron config registers (vth, decay, grow, etc.)
//     2. Load synaptic weights + biases from file into all layers
//     3. Drive input spikes sample-by-sample for NUM_STEP timesteps
//     4. Collect output spikes, write to output files
//
// ─── Test Sequence ──────────────────────────────────────────────
//
//   Phase 1 - Reset + Configuration
//     Assert rst, program 6 neuron config registers via cfg_write.
//
//   Phase 2 - Weight Loading
//     Read WTS_CNT weight entries from file (address + data pairs).
//     Program via mem_write / bias_write based on address MSBs.
//
//   Phase 3 - Inference
//     For each of SIM_CNT input samples:
//       - Assert rst_neuron to clear LIF state (weights preserved)
//       - Drive inspk from input spike file for NUM_STEP timesteps
//       - Pad PAD_SAMPLES zero-spike cycles between samples
//       - Record spk_out to output files each spkclk cycle
//
// ─── Clock Generation ───────────────────────────────────────────
//
//   memclk:  MEM_CLK_PERIOD (fast - drives BRAM + MAC)
//   spkclk:  SPK_CLK_PERIOD = MAX_NEURON × MEM_CLK_PERIOD + CLK_BFR
//            (slow - drives LIF neuron updates)
//   prgclk:  PRG_CLK_PERIOD = 2 × MEM_CLK_PERIOD
//            (weight programming clock)
//
// ─── Parameters ─────────────────────────────────────────────────
//
//   All parameters inherited from parameters.svh and cnn_config.svh.
//   Key values: SIM_CNT (number of samples), NUM_STEP (timesteps
//   per sample), WTS_CNT (total weights to program).
//   It is notable that the SIM_CNT should be adjusted per each input file!
// -----------------------------------------------------------------------------*/

`timescale 1ns / 1ps
`include "parameters.svh"
`include "cnn_config.svh"
	
module tb_scnncore #(
	localparam IN_CHANNEL = cnn_config[0][3],
	localparam FANIN_FLAT = FANIN * IN_CHANNEL
)();
   // DUT signals
    reg memclk;
    reg spkclk;
    reg prgclk;
    reg rst;
	reg rst_neuron;
    reg wr_en;
    int wr_addr;
    int wr_data;
    reg [FANIN-1:0] inspk [IN_CHANNEL-1:0];


	localparam WTS_CFG_CNT = WTS_CNT + CONFIG_REG;
	localparam OUT_CH_L1 = cnn_config [1][4];
	localparam FANOUT_FM_L1 = cnn_config [1][5]*cnn_config [1][6];

	localparam OUT_CH_L0 = cnn_config [0][4];
	localparam FANOUT_FM_L0 = cnn_config [0][5]*cnn_config [0][6];


	// ──bias count — Conv1 (16) + Conv2 (32) = 48 total ────
	localparam BIAS_CNT_L0 = cnn_config[0][4];  // 16
	localparam BIAS_CNT_L1 = cnn_config[1][4];  // 32
	localparam BIAS_CNT = BIAS_CNT_L0 + BIAS_CNT_L1;  // 48
	// ─────────────────────────────────────────────────────────────


    wire [FANOUT-1:0]outspk;
	// File paths
	string wtFname       = {INSTALL_DIR, "/hw_q3_4/fold2/weight/snncore.synaptic_weight.txt"};
	string addrFname     = {INSTALL_DIR, "/hw_q3_4/fold2/weight/snncore.synaptic_address.txt"};
	string biasFname     = {INSTALL_DIR, "/hw_q3_4/fold2/weight/snncore.bias_values.txt"};
	string biasAddrFname = {INSTALL_DIR, "/hw_q3_4/fold2/weight/snncore.bias_addresses.txt"};


    string ispkFname     = {INSTALL_DIR, "/hw_q3_4/fold2/input/snncore.spikes_input_moderate_0_124.txt"};
	string ospkFname     = {INSTALL_DIR, "/hw_q3_4/fold2/output/snncore.spikes_output_moderate_0_124.txt"};

	// ─────────────────────────────────────────────────────────────


    // Weight/config memory
	int mem_data [WTS_CFG_CNT-1:0];
	int mem_addr [WTS_CFG_CNT-1:0];

	// ──bias memory ─────────────────────────────────────────
	int bias_data [BIAS_CNT-1:0];
	int bias_addr [BIAS_CNT-1:0];
	// ─────────────────────────────────────────────────────────────


	// Spike buffers
	reg [FANIN_FLAT-1:0] inspk_bfr [SIM_CNT-1:0];
	reg [FANOUT-1:0] ospk_bfr [SIM_CNT+EXTRA_CYCLES-1:0];	//output spike buffer

    reg inp_en;
	reg out_en;
 
	int inp_cnt;
	int step_cnt;
	int out_cnt;
	int wrcnt;
	int file;
	int i;
	int N_SAMPLES = 50;

	// ── bias loading signals ────────────────────────────────
	reg bias_wr_en;
	int bias_wrcnt;
	// ─────────────────────────────────────────────────────────────

   // Instantiate DUT
   scnncore #(
   )
   scnncore_dut (
		.mem_write(mem_write),
		.cfg_write(cfg_write),
		.bias_write(bias_write),
		.wr_addr(wr_addr),
       	.wr_data(wr_data),
    	.rst(rst),
		.rst_neuron(rst_neuron),
       	.memclk(memclk),
       	.spkclk(spkclk),
	   	.spk_in(inspk),
		.spk_out(outspk)
   );

   //define all clocks
	always #SPK_CLK_PERIOD 	spkclk 	= ~spkclk;
	always #MEM_CLK_PERIOD 	memclk 	= ~memclk;
	always #PRG_CLK_PERIOD 	prgclk 	= ~prgclk;

   // ── Weight + config write controller
	always @(posedge prgclk or posedge rst) begin
		if (rst) begin
			wrcnt <= 0;
		end
		else begin
			if (wr_en) begin
				if (wrcnt == WTS_CFG_CNT) begin
					wr_en <= 0;
					wrcnt <= 0;
				end
				else begin
					wrcnt  <= wrcnt + 1;
                   	wr_addr <= mem_addr[wrcnt];
                   	wr_data <= mem_data[wrcnt];
				end
			end
		end
	end

	assign mem_write = (wrcnt < WTS_CNT)? wr_en : 0;
	assign cfg_write = (wrcnt >= WTS_CNT)? wr_en : 0;

	// ──Bias write controller ───────────────────────────────
	// Runs after weight/config loading completes.
	// Drives wr_addr and wr_data with bias values while bias_wr_en=1.
	always @(posedge prgclk or posedge rst) begin
		if (rst) begin
			bias_wrcnt <= 0;
		end
		else begin
			if (bias_wr_en) begin
				if (bias_wrcnt == BIAS_CNT) begin
					bias_wr_en <= 0;
					bias_wrcnt <= 0;
				end
				else begin
					bias_wrcnt <= bias_wrcnt + 1;
					wr_addr    <= bias_addr[bias_wrcnt];
					wr_data    <= bias_data[bias_wrcnt];
				end
			end
		end
	end
 
	assign bias_write = bias_wr_en;
	

	// ── Spike input controller ───────────────────────────────────
	// Read from flat 300-bit buffer and split into 3 channels of 100 bits
	always @(posedge spkclk or posedge rst) begin
		if (rst) begin
			inp_cnt <= 0;
			step_cnt   <= 0;
		end
		else begin
			if (inp_en) begin
				if (inp_cnt == SIM_CNT-1) begin
					inp_en  <= 0;
					inp_cnt <= 0;
				end
				else begin
					inp_cnt <= inp_cnt + 1;
				end
 
				for (int ch = 0; ch < IN_CHANNEL; ch++) begin
					inspk[ch] <= inspk_bfr[inp_cnt][ch*FANIN +: FANIN];
				end
			end
			else begin
				for (int ch = 0; ch < IN_CHANNEL; ch++) begin
					inspk[ch] <= '0;
				end
			end
		end
	end


    localparam IMG_PERIOD = NUM_STEP + PAD_SAMPLES;
    always @(posedge spkclk or posedge rst) begin
        if (rst) begin
            rst_neuron <= 1'b0;
        end
        else if (inp_en) begin
            if (inp_cnt >= IMG_PERIOD && (inp_cnt + 1) % IMG_PERIOD == PAD_SAMPLES)
                rst_neuron <= 1'b1;
            else
                rst_neuron <= 1'b0;
        end
        else begin
            rst_neuron <= 1'b0;
        end
    end


   // Output capture controller
	always @(posedge spkclk or posedge rst) begin
		if (rst) begin
			out_cnt <= 0;
		end
		else begin
			if (out_en) begin
				if (out_cnt == SIM_CNT+EXTRA_CYCLES-1) begin
					out_cnt <= 0;
					out_en	<= 0;
				end
                else begin
					out_cnt <= out_cnt + 1;
				end
				ospk_bfr[out_cnt] <= outspk;
			end
		end
	end


   // Test stimulus
   initial begin
       $display("=== snncore Test Start ===");

        spkclk 	= 0;
		memclk 	= 0;
		rst 	= 0;
		wr_en 	= 0;
		wr_data = 0;
		inp_en  = 0;
		out_en  = 0;
		inp_cnt = 0;
		out_cnt = 0;
		prgclk 	= 0;
		wrcnt	= 0;
		bias_wr_en = 0;     
		bias_wrcnt = 0;    

       // Reset
		#DELAY;
		rst 	= 1;
		#DELAY;
		rst 	= 0;
        

        // ════════════════════════════════════════════════════════
		// Phase 1: Load weights
		// ════════════════════════════════════════════════════════
		file=$fopen(wtFname,"r");	
		if (file)
			$display("%s was opened successfully", wtFname);
		else
			$display("%s NOT opened", wtFname);
		for (i=0; i<WTS_CNT; i=i+1) begin
			$fscanf(file,"%h",mem_data[i]);
		end
		$fclose(file);

		// Read weight addresses
		file=$fopen(addrFname,"r");	
		if (file)
			$display("%s was opened successfully", addrFname);
		else
			$display("%s NOT opened", addrFname);
		for (i=0; i<WTS_CNT; i=i+1) begin
			$fscanf(file,"%h",mem_addr[i]);
			//wts.push_back(wt);
		end
		$fclose(file);

		//config registers
		i = 0;
		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = VTH;
		i = i + 1;

		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = DECAY_RATE;
		i = i + 1;

		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = GROW_RATE;
		i = i + 1;

		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = VREST;
		i = i + 1;

		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = RESET_MECHANISM;
		i = i + 1;

		mem_addr[i+WTS_CNT] = i;
		mem_data[i+WTS_CNT] = REFRACTORY_PERIOD;
		i = i + 1;


		// Drive weights + config to DUT
		#DELAY;
		wr_en = 1;
		@(negedge wr_en);
		$display("Weights and config loaded.");


		// ════════════════════════════════════════════════════════
		// Phase 2: Load biases (NEW)
		// ════════════════════════════════════════════════════════
		// Bias file format: one hex value per line.
		// First BIAS_CNT_L0 lines = Conv1 biases (layer 0, channels 0..15)
		// Next  BIAS_CNT_L1 lines = Conv2 biases (layer 1, channels 0..31)
		// Address file format: one hex address per line (includes layer select bits)
		file = $fopen(biasFname, "r");
		if (file)
			$display("%s was opened successfully", biasFname);
		else
			$display("%s NOT opened", biasFname);
		for (i = 0; i < BIAS_CNT; i = i + 1) begin
			$fscanf(file, "%h", bias_data[i]);
		end
		$fclose(file);
 
		file = $fopen(biasAddrFname, "r");
		if (file)
			$display("%s was opened successfully", biasAddrFname);
		else
			$display("%s NOT opened", biasAddrFname);
		for (i = 0; i < BIAS_CNT; i = i + 1) begin
			$fscanf(file, "%h", bias_addr[i]);
		end
		$fclose(file);
 
		// Drive biases to DUT
		// #DELAY;
		bias_wr_en = 1;
		@(negedge bias_wr_en);
		$display("Biases loaded (Conv1: %0d, Conv2: %0d).", BIAS_CNT_L0, BIAS_CNT_L1);




        // ════════════════════════════════════════════════════════
		// Phase 3: Load input spikes and run inference
		// ════════════════════════════════════════════════════════
		file = $fopen(ispkFname, "r");
		if (file) $display("%s opened", ispkFname);
		else      $display("ERROR: %s NOT opened", ispkFname);
		for (i = 0; i < SIM_CNT; i = i + 1) begin
			$fscanf(file, "%b", inspk_bfr[i]);   // read full 300-bit line
		end
		$fclose(file);
		
        #DELAY;
        @(posedge spkclk);
        rst_neuron = 1;
        @(posedge spkclk);
        rst_neuron = 0;
        @(posedge spkclk);
        inp_en = 1;

		#DELAY;
		@(posedge spkclk);
		#1500
		out_en = 1;
 
		// Wait for output capture to complete
		@(negedge out_en);
		@(posedge spkclk);
		#DELAY;
		@(posedge spkclk);
 
		// Write output spikes
		file = $fopen(ospkFname, "w");
		for (i = 0; i < SIM_CNT + EXTRA_CYCLES; i = i + 1) begin
			$fwrite(file, "%b \n", ospk_bfr[i]);
		end
		$fclose(file);
	
		$display("=== SpO2 scnncore Test End ===");
   end

endmodule
