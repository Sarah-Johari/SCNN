# Folding Timing Budget

## Overview

In the folded CNN architecture, P output channels are computed in parallel per phase.
The total number of phases is `NUM_PHASES = ceil(OUT_CHANNEL / P)`.
All phases must complete within one `spkclk` period (`T_spkclk` memclk cycles).

---

## Per-Phase Cycle Counts

| Phase            | FSM States                     | Memclk Cycles    |
|------------------|--------------------------------|------------------|
| Phase 0          | PH_WAIT_SA                     | MEM_SIZE + 3     |
| Phases 1..N-1    | PH_RST_MAC + PH_SWEEP + PH_FLUSH | 1 + MEM_SIZE + 3 = MEM_SIZE + 4 |
| Done             | PH_DONE                        | 1                |

Where the +3 in Phase 0 accounts for:
- 1 cycle: syn_access_cnn DONE state
- 2 cycles: pipeline flush (BRAM read latency + psum registration)

---

## Total Cycle Derivation

```
T_total = (MEM_SIZE + 3) + (NUM_PHASES - 1) * (MEM_SIZE + 4) + 1
        = (MEM_SIZE + 4) + (NUM_PHASES - 1) * (MEM_SIZE + 4)
        = (MEM_SIZE + 4) * [1 + (NUM_PHASES - 1)]
        = (MEM_SIZE + 4) * NUM_PHASES
```

### Final Formula

```
T_total = NUM_PHASES * (MEM_SIZE + 4)
```

Where:
- `MEM_SIZE = X_KERNEL * Y_KERNEL`
- `NUM_PHASES = ceil(OUT_CHANNEL / P)`

---

## Timing Constraint

All phases must fit within one spkclk period:

```
T_total <= T_spkclk

NUM_PHASES * (MEM_SIZE + 4) <= T_spkclk
```

### Solving for Minimum P

```
NUM_PHASES_max = floor(T_spkclk / (MEM_SIZE + 4))

P_min = ceil(OUT_CHANNEL / NUM_PHASES_max)
```

---

## Example: SpO2 Network

### System Parameters

```
T_spkclk = 295 memclk cycles   (memclk = (288 + 7) * spkclk)
```

### CNN Layer 0

```
Kernel:      1 x 5       → MEM_SIZE = 5
Input:       1 x 100
In channels: 9
Out channels: 16
Stride:      2

NUM_PHASES_max = floor(295 / (5 + 4)) = floor(295 / 9) = 32
P_min          = ceil(16 / 32) = 1

With P = 1:
  NUM_PHASES = 16
  T_total    = 16 * 9 = 144 cycles
  Margin     = 295 - 144 = 151 cycles
```

### CNN Layer 1

```
Kernel:      1 x 5       → MEM_SIZE = 5
In channels: 16
Out channels: 32
Stride:      5

NUM_PHASES_max = floor(295 / (5 + 4)) = floor(295 / 9) = 32
P_min          = ceil(32 / 32) = 1

With P = 1:
  NUM_PHASES = 32
  T_total    = 32 * 9 = 288 cycles
  Margin     = 295 - 288 = 7 cycles
```

### Summary

| Layer | OUT_CH | P_min | NUM_PHASES | T_total | Margin |
|-------|--------|-------|------------|---------|--------|
| CNN 0 | 16     | 1     | 16         | 144     | 151    |
| CNN 1 | 32     | 1     | 32         | 288     | 7      |

Both layers fit with P = 1 (maximum area savings).
Layer 1 is the bottleneck with only 7 cycles of margin.
