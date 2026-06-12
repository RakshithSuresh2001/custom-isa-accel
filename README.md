# custom-isa-accel

A hardware neural network accelerator built around a custom RISC-V ISA extension. The project adds three new instructions to a 5-stage RV32I pipeline that offload 8x8 matrix multiply to a weight-stationary systolic array, connected over an AXI-Lite interface.

The RTL was verified with directed simulation and taken through the full ASAP7 7nm physical design flow using OpenROAD.

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    cpu_top                          │
│                                                     │
│  ┌────────┐  ┌────────┐  ┌──────────────────────┐  │
│  │ Fetch  │→ │ Decode │→ │       Execute        │  │
│  └────────┘  └────────┘  │  (AXI-Lite Master)   │  │
│                           └──────────┬───────────┘  │
│  ┌────────┐  ┌──────────┐           │              │
│  │  BHT   │  │  Hazard  │←──────────┘              │
│  └────────┘  └──────────┘  accel_stall             │
└─────────────────────────────────────────────────────┘
                    │ AXI-Lite
┌───────────────────▼─────────────────────────────────┐
│                 accel_wrapper                        │
│                                                     │
│  ┌─────────────────────┐  ┌────────────────────┐   │
│  │      accel_top      │  │     scratchpad     │   │
│  │  (Control FSM)      │↔ │  A: 64×8b  (acts) │   │
│  │                     │  │  B: 64×8b  (wgts) │   │
│  │  ┌───────────────┐  │  │  C:  8×32b (res)  │   │
│  │  │ systolic_array│  │  └────────────────────┘   │
│  │  │   8×8 PEs     │  │                           │
│  │  │ weight-stat.  │  │                           │
│  │  └───────────────┘  │                           │
│  └─────────────────────┘                           │
└─────────────────────────────────────────────────────┘
```

### Custom ISA Extension (custom-0, opcode `7'b0001011`)

Three new instructions extend RV32I. The decode stage recognizes them and routes to the AXI-Lite master in execute. `MMUL` stalls the pipeline via the hazard unit until `accel_done` pulses.

| Instruction | funct3 | rs1 | rs2 | Operation |
|---|---|---|---|---|
| `MLOAD` | `3'b000` | base addr | matrix_id (0=A, 1=B) | Load matrix from scratchpad into systolic array |
| `MMUL` | `3'b001` | — | — | Kick compute FSM, stall pipeline until done |
| `MSTORE` | `3'b010` | dest addr | — | Write result matrix C to destination |

Instruction encoding:

```
31      25 24  20 19  15 14  12 11   7 6      0
| funct7  |  rs2  |  rs1  |funct3|  rd   | opcode |
| 0000000 |  rs2  |  rs1  | 000  | 00000 | 0001011 |  MLOAD
| 0000000 | 00000 | 00000 | 001  | 00000 | 0001011 |  MMUL
| 0000000 | 00000 |  rs1  | 010  | 00000 | 0001011 |  MSTORE
```

### Systolic Array

8x8 weight-stationary dataflow. Weights are loaded row by row via the `weight_load` interface. Activations enter the left edge diagonally skewed, one row per cycle. Partial sums accumulate vertically. Each column output peaks 12 cycles after its activation enters, staggered by one cycle per column.

The control FSM handles the full sequence: weight loading (3 cycles per SRAM read), activation loading, diagonal feed, and result capture at the exact cycle each column peaks.

---

## RTL Structure

```
custom-isa-accel/
├── rtl/
│   ├── cpu/
│   │   ├── fetch.sv
│   │   ├── decode.sv          # extended with custom-0 opcode
│   │   ├── execute.sv         # AXI-Lite master + accel_stall
│   │   ├── hazard.sv          # accel_stall OR load-use stall
│   │   ├── regfile.sv
│   │   ├── memory_stage.sv
│   │   ├── writeback.sv
│   │   └── bht.sv             # 2-bit saturating branch predictor
│   ├── accel/
│   │   ├── accel_wrapper.sv   # top-level accelerator
│   │   ├── accel_top.sv       # AXI-Lite slave + control FSM
│   │   ├── scratchpad.sv      # 160-byte register-based scratchpad
│   │   ├── systolic_array.sv  # 8x8 PE grid
│   │   ├── systolic_array_wrap.sv  # flat-bus wrapper for Yosys
│   │   └── pe.sv              # MAC processing element
│   └── top/
│       └── cpu_top.sv         # full system integration
├── tb/
│   ├── accel_wrapper_tb.sv    # unit tests (2 test cases)
│   └── tb_cpu_accel.sv        # CPU-level pipeline test
└── sim/
    ├── run_accel_tb.sh
    ├── run_cpu_tb.sh
    └── run_all_tb.sh
```

---

## Verification

### Test Results

```
Test 1: Identity weight matrix, activations 1..8
  Expected: psum[c] = c+1
  Result:   8/8 PASS

Test 2: All-ones weight matrix, activations 1..8
  Expected: psum[c] = 36 (sum of 1..8)
  Result:   8/8 PASS

Test 3: CPU pipeline — MLOAD/MMUL/MSTORE through 5-stage pipeline
  Expected: psum[c] = c+1, pipeline resumes correctly after MSTORE
  Result:   11/11 PASS
```

### Running the tests

```bash
# Unit tests (accelerator only)
cd sim && ./run_accel_tb.sh

# CPU-level test
cd sim && ./run_cpu_tb.sh

# All tests
cd sim && ./run_all_tb.sh
```

Simulation uses Icarus Verilog (`iverilog -g2012`). No additional dependencies.

---

## Physical Design — ASAP7 7nm

Full RTL-to-GDS flow using OpenROAD. The systolic array scratchpad uses register-based memory (swap to Fakeram macros for area-optimized PD).

### Results

| Metric | Value |
|---|---|
| Standard cells | 11,562 |
| Design area | 1,515 µm² |
| Core utilization | 34% |
| Clock target | 500MHz (2.0ns period) |
| WNS | -645ps |
| Achievable frequency | ~756MHz |
| DRC violations | 0 (OpenROAD DRC clean) |

WNS of -645ps on the first pass with default PDN settings. Achievable frequency is ~756MHz with timing-driven placement and PDN tuning. The IR drop report reflects an undersized PDN for this design size, which is the primary optimization target for the next iteration.

### GDS Layout

![GDS Layout](pd/results/gds_layout.png)

### Flow

```bash
cd ~/OpenROAD-flow-scripts/flow
make DESIGN_CONFIG=./designs/asap7/custom-isa-accel/config.mk
```

---

## Key Design Decisions

**Why a custom ISA extension instead of MMIO?**
MMIO-mapped accelerator control is simpler to implement but doesn't require touching the pipeline. Extending the decode and execute stages with real custom opcodes means the CPU actually stalls on `MMUL` via the hazard unit, which is the correct hardware behavior and a stronger story for interviews.

**Why weight-stationary dataflow?**
Weight-stationary keeps weights fixed in each PE across multiple input activations, which minimizes weight memory bandwidth. For a small 8x8 array targeting inference workloads, this trades accumulator complexity for reduced SRAM pressure.

**Why register-based scratchpad?**
For a 160-byte scratchpad (64B matrix A + 64B matrix B + 32B result C), register arrays synthesize cleanly and avoid SRAM macro dependency during simulation. Swapping to Fakeram macros for the ASAP7 flow is straightforward and would reduce area significantly.

---

## Tools

| Tool | Version | Purpose |
|---|---|---|
| Icarus Verilog | 12.0 | RTL simulation |
| Yosys | 0.44 | Synthesis |
| OpenROAD | 2.0 | Place and route |
| KLayout | 0.28 | GDS viewing |
| ASAP7 PDK | — | 7nm standard cell library |

---

## Author

Rakshith Suresh
MS Electrical Engineering, USC Viterbi School of Engineering
[GitHub](https://github.com/RakshithSuresh2001) | [LinkedIn](https://linkedin.com/in/rakshith-suresh-890329258/)
