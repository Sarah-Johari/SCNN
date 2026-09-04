# SCNN: Spiking Convolutional Neural Network Accelerator

A configurable spiking CNN accelerator for FPGA deployment. Built upon [QuantiSenc](https://github.com/drexel-disco/quantisenc), a quantized spike-enabled neural core design.

## Architecture

The accelerator implements a 4-layer feed-forward spiking neural network:

```
CNN Layer 0 → CNN Layer 1 → FC Layer 0 → FC Layer 1
(conv + LIF)   (conv + LIF)   (288→64)     (64→3)
```

All output channels are computed in parallel within each CNN layer. Each (output_channel, input_channel) pair has its own BRAM and MAC datapath.

## Directory Structure

```
src/           RTL source files (SystemVerilog/Verilog)
  ├── scnncore.sv               Top-level accelerator core
  ├── cnn_layer.sv              Spiking convolutional layer
  ├── fc_layer.sv               Fully-connected spiking layer
  ├── bmem_cnn.sv               BRAM + MAC datapath (CNN)
  ├── bmem_fc.sv                BRAM + MAC datapath (FC)
  ├── syn_access_cnn.sv         Read address sequencer (CNN)
  ├── syn_access_fc.sv          Read address sequencer (FC)
  ├── cuba_lif.sv               FC neuron (bmem + LIF wrapper)
  ├── bias_store_gated.sv       Bias storage + spike gating
  ├── xchan_bias_acc.sv         Cross-channel accumulator + bias adder
  ├── pooling.sv                Activation pooling (MAX/MIN/none)
  ├── lif.v                     Leaky integrate-and-fire neuron
  ├── qadd.v                    Quantized saturating adder
  ├── qmul.v                    Quantized multiplier (bug-fixed)
  ├── qalu.v                    Quantized ALU
  ├── twos_complement.v         Two's complement converter
  ├── vector_sampler.sv         Single-vector sampling register
  ├── multibit_sampler.sv       Multi-element array sampling register
  ├── bram_decoder.sv           BRAM write address decoder
  ├── parameterized_decoder.sv  Parameterized N-to-M decoder
  ├── decoder_neuron_config.sv  Neuron config register decoder
  ├── cnn_config.svh            Per-layer CNN configuration
  └── parameters.vh             System-level parameters
tb/            Testbenches for individual modules and integration
xdc/           Constraints file for FPGA synthesis
weight/        Synaptic weights and addresses for hardware programming
input/         Spike input data for hardware testing
output/        Spike and vmem output collected from hardware
```

## Key Features

- **Configurable precision:** 8, 12, or 16-bit fixed-point (INTEGER_PRECISION + DECIMAL_PRECISION).
- **Bias gating:** Suppresses bias accumulation until the first input spike arrives, preventing neuron drift.
- **Dual-clock architecture:** Fast `memclk` for BRAM access and MAC operations, slow `spkclk` for LIF neuron updates.
- **Modular design:** CNN layer decomposed into reusable sub-modules (bias_store_gated, xchan_bias_acc).

## Bug Fixes

The quantized multiplier (`qmul.v`) includes two bug fixes from the original QuantiSenc implementation:

1. **Sign-aware saturation:** Overflow/underflow now saturate to the correct sign (was always positive).
2. **Overflow priority:** When both overflow and underflow assert, overflow takes priority (was backwards).

See the file header for details.

## Acknowledgments

This project builds upon [QuantiSenc](https://github.com/drexel-disco/quantisenc), an open-source spiking neuromorphic hardware design developed at Drexel University's DISCO Lab. The following modules were adapted from that project: `qadd.v`, `qmul.v`, `qalu.v`, `twos_complement.v`, `lif.v`, `bmem_fc.sv`, `fc_layer.sv`, `syn_access_fc.sv`, `cuba_lif.sv`.

## Bug Reporting

If you find any bug in the design, please email Sarah Johari ([sj984@drexel.edu](mailto:sj984@drexel.edu)).

## Citation

If you find this code useful in your research, please cite our paper:
```
@misc{johari2026reconfigurablehybridconvolutionalfullyconnected,
      title={A Reconfigurable Hybrid Convolutional-Fully Connected Neuromorphic Core for Biomedical Edge Inference}, 
      author={Sarah Johari and Suman Kumar and Abhishek Mishra and Anush Lingamoorthy and Nagarajan Kandasamy},
      year={2026},
      eprint={2609.03174},
      archivePrefix={arXiv},
      primaryClass={eess.SY},
      url={https://arxiv.org/abs/2609.03174}, 
}
```