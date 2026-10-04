# PQC
4_1 semester project on Keccak
Video:
https://drive.google.com/file/d/1pPm-UPyuYmzK-0nBejH3o-XKQMv3bkUT/view?usp=drive_link


# Hardware Implementation of Keccak (SHA-3 / SHAKE) for Post-Quantum Cryptography

> A synthesisable RTL implementation of the Keccak sponge construction in Verilog, supporting SHA-256, SHA-512, SHAKE-128, and SHAKE-256. Motivated by the role of Keccak as a foundational primitive in NIST Post-Quantum Cryptography standards — Kyber and Dilithium.

---

## Table of Contents

- [Background and Motivation](#background-and-motivation)
- [What is Keccak?](#what-is-keccak)
- [Supported Modes](#supported-modes)
- [Architecture Overview](#architecture-overview)
- [Module Descriptions](#module-descriptions)
- [Handshaking and Dataflow](#handshaking-and-dataflow)
- [Repository Structure](#repository-structure)
- [Simulation and Verification](#simulation-and-verification)
- [How to Run](#how-to-run)
- [References](#references)

---

## Background and Motivation

Post-Quantum Cryptography (PQC) refers to cryptographic algorithms designed to be secure against attacks from quantum computers. In 2022, NIST standardised several PQC schemes — most notably **Kyber** (key encapsulation) and **Dilithium** (digital signatures). Both of these schemes rely heavily on the **Keccak sponge construction** as their underlying hash primitive, through the SHAKE and SHA-3 function families.

While software implementations of Keccak are straightforward, deploying PQC in constrained or high-performance hardware environments — such as embedded security chips, FPGAs, or ASICs — demands an efficient RTL-level implementation. This project is a study in exactly that: building a complete, working hardware implementation of Keccak from scratch in synthesisable Verilog, understanding every architectural decision along the way.

---

## What is Keccak?

Keccak is a cryptographic sponge function designed by Bertoni, Daemen, Peeters, and Van Assche, and selected as the SHA-3 standard by NIST in 2012. It operates on a **1600-bit state** organised as a 5×5 array of 64-bit lanes.

The sponge construction has two phases:

- **Absorb phase**: The input message (after padding) is XOR-ed into the state block by block, with each block being the size of the rate `r`. After each block is absorbed, the Keccak-f[1600] permutation is applied.
- **Squeeze phase**: The output hash (or extendable output, in the case of SHAKE) is read from the state's rate portion, with further permutations applied if more output is needed.

The Keccak-f[1600] permutation itself consists of **24 rounds**, each applying five sub-steps to the state: **θ (Theta)**, **ρ (Rho)**, **π (Pi)**, **χ (Chi)**, and **ι (Iota)**.

---

## Supported Modes

The design supports four operating modes, selectable via a 2-bit `mode` input at runtime:

| Mode Value | Function  | Rate (r) | Capacity (c) | Output Length |
|:---:|:---:|:---:|:---:|:---:|
| `2'b00` | SHA-256   | 1088 bits (17 lanes) | 512 bits | 256 bits |
| `2'b01` | SHA-512   | 576 bits (9 lanes)   | 1024 bits | 512 bits |
| `2'b10` | SHAKE-128 | 1344 bits (21 lanes) | 256 bits | Extendable |
| `2'b11` | SHAKE-256 | 1088 bits (17 lanes) | 512 bits | Extendable |

For SHAKE modes, the `squeeze` signal allows the consumer to terminate output generation at any point, providing the extendable-output (XOF) behaviour defined by the standard.

---

## Architecture Overview

The top-level module `keccak` (defined in `keccak_v1.v`) instantiates and orchestrates six sub-modules in a producer-consumer pipeline. The overall data path flows as follows:

```
Input (64-bit lanes)
       │
       ▼
   [ padder ]  ──── mode-aware padding, rate counter, domain separation
       │
       ▼
   [ SIPO ]    ──── accumulates 64-bit lanes into a full rate-width block (1344 bits)
       │
       ▼
[ f_permutation ] ── 24-round Keccak-f[1600], absorb + squeeze control
       │   ▲
       │   └──── [ rconst ] ── ROM-based round constant LUT
       │
       ▼
   [ PISO ]    ──── serialises 1344-bit squeezed state into 64-bit output words
       │
       ▼
 [ Sync_FIFO ] ──── buffers output words, decouples permutation from consumer
       │
       ▼
Output (64-bit words, `out_valid` gated)
```

The `mode` register is latched on `start_calc` and held stable through the entire hash operation, ensuring consistent rate selection across all sub-modules.

---

## Module Descriptions

### `keccak` — Top-Level Orchestrator (`keccak_v1.v`)

The root module. It accepts a 64-bit serial input stream and produces a 64-bit serial hash output. It holds the `mode` register, drives `hash_init` on reset or `start_calc`, manages the `absorb_done` flag to gate squeeze operations, and tracks output word count via `cntr_out` to know when the hash output is fully drained. All sub-modules are instantiated and wired here.

Key signals:

| Signal | Direction | Description |
|:---|:---:|:---|
| `in [63:0]` | Input | 64-bit message lane input |
| `mode [1:0]` | Input | Hash mode selector |
| `in_valid` | Input | Indicates current input word is valid |
| `is_last` | Input | Flags the last input word of the message |
| `start_calc` | Input | Initialises a new hash operation |
| `gimme` | Input | Consumer requests next output word |
| `ack` | Output | Padder acknowledges input acceptance |
| `out [63:0]` | Output | 64-bit hash output word |
| `out_valid` | Output | Indicates a valid output word is present |

---

### `padder` — Message Padding (`padder.v`)

The padder is responsible for framing the input message according to the Keccak padding rule before it is absorbed into the permutation. It maintains a down-counter (`cntr`) initialised to the number of 64-bit lanes in one rate block (17 for SHA-256/SHAKE-256, 9 for SHA-512, 21 for SHAKE-128). As each valid input lane is accepted, the counter decrements. When `is_last` is asserted, the padder inserts the domain-separation and padding bits — a `0x01` byte at the position after the last message byte, followed by zeros, and a `0x80` byte at the end of the rate block — in accordance with the Keccak specification. The `out_ready` signal tells the SIPO that a valid, padded lane is available.

---

### `SIPO` — Serial-In Parallel-Out Register (`SIPO.v`)

The SIPO accumulates incoming 64-bit padded lanes into a single wide rate-block register of 1344 bits (the maximum rate, for SHAKE-128). It left-shifts on each load, appending each new lane. When the padder signals `cntr_zero` (counter reached 1, meaning the final lane of the block is being loaded), the SIPO asserts `is_loaded`, informing `f_permutation` that a complete block is ready for absorption.

---

### `f_permutation` — Keccak-f[1600] Permutation Engine (`f_permutation.v`)

This is the core computational block. It manages a 23-bit one-hot shift register `i[22:0]` that sequences through the 24 rounds of Keccak-f[1600]. On `accept` (triggered when `in_ready` is high and the permutation is idle), the incoming block is XOR-absorbed into the current state at the appropriate rate width for the selected mode, and the round counter begins shifting. On each clock edge while `calc` is asserted, the state passes through the combinational `round` module and is registered back. When `i[22]` is reached (the 24th round), `out_ready` is asserted and the final state is held for squeezing.

The XOR absorption is mode-selective:

- SHA-512 (mode 1): XOR the lower 576 bits of the rate block into the top 576 bits of state
- SHA-256 / SHAKE-256 (mode 0/3): XOR 1088 bits
- SHAKE-128 (mode 2): XOR the full 1344-bit block

For SHAKE modes, the `squeeze` signal triggers further permutations to generate extended output, gated by `gimme` from the consumer.

---

### `round` — Single Keccak Round, Pure Combinational Logic (`round.v`)

The `round` module implements one complete Keccak-f round as **purely combinational logic** — no clock, no registers. It takes the 1600-bit state and 64-bit round constant as inputs and produces the next 1600-bit state in a single combinational pass. All five sub-steps are implemented:

- **θ (Theta)**: XORs each lane with the column parities of adjacent columns, providing diffusion across the state
- **ρ (Rho)**: Rotates each of the 25 lanes by a fixed, lane-specific offset, providing intra-lane diffusion
- **π (Pi)**: Permutes the positions of the 25 lanes within the 5×5 array, providing inter-lane diffusion
- **χ (Chi)**: Applies a non-linear transformation row-wise using AND and NOT operations — this is the only non-linear step in the round
- **ι (Iota)**: XORs a round-specific constant into lane (0,0) to break symmetry between rounds

Macro-based position indexing (`high_pos`, `low_pos`) and `generate` loops keep the implementation clean and directly traceable to the Keccak specification.

---

### `rconst` — Round Constant ROM (`rconst.v`)

A purely combinational look-up table that maps the 24-bit round index (derived from `f_permutation`'s shift register and `accept` signal) to the corresponding 64-bit Keccak round constant. Only the 7 defined bit positions of each round constant (indices 0, 1, 3, 7, 15, 31, 63) are computed via OR logic over the relevant round index bits; all others remain zero. This is an efficient encoding of the Keccak round constant schedule.

---

### `PISO` — Parallel-In Serial-Out Register (`PISO.v`)

Once the permutation completes, the top 1344 bits of the 1600-bit output state (the rate portion) are loaded into the PISO register. On each cycle where `shift_en` is active (FIFO is not full and output count has not reached zero), the register shifts left by 64 bits, placing the next output word at the MSB position for reading. The `pack` signal (tied to `load_en`) informs `f_permutation` to clear `out_ready`, preventing it from re-triggering until the next squeeze.

---

### `Sync_FIFO` — Synchronous Output Buffer (`Sync_FIFO.v`)

A standard synchronous FIFO with a 64-entry depth (BUF_WIDTH = 6), 64-bit data width, and separate read/write pointers. It decouples the rate at which the PISO produces output words from the rate at which the downstream consumer (`gimme` handshake) reads them. `buf_full` feeds back to inhibit PISO shifting when the buffer is saturated; `buf_empty` feeds back to the top-level squeeze logic to know when more permutation output is needed.

---

## Handshaking and Dataflow

The design uses a distributed handshaking protocol to ensure correct data flow across the pipeline:

1. The consumer asserts `in_valid` with each input word. The padder responds with `ack` when the word is accepted.
2. `start_calc` resets the hash state and latches the `mode`, triggering a new hash operation.
3. `is_last` marks the final input word, causing the padder to apply the closing padding sequence.
4. Once the SIPO accumulates a full block (`is_loaded`), `f_permutation` begins absorbing and computing.
5. After 24 rounds, `out_ready` is asserted; the PISO loads the state and begins serialising output into the FIFO.
6. The consumer asserts `gimme` to read output words one at a time; `out_valid` qualifies each valid output word.
7. For SHAKE modes, `squeeze` triggers additional permutations as long as `gimme` is active and the FIFO is drained.

---

## Repository Structure

```
.
├── keccak_v1.v          # Top-level keccak module
├── padder.v             # Message padding and rate counter
├── SIPO.v               # Serial-In Parallel-Out accumulation register
├── f_permutation.v      # Keccak-f[1600] permutation engine
├── round.v              # Single round — purely combinational (θ ρ π χ ι)
├── rconst.v             # Round constant ROM (24 constants)
├── PISO.v               # Parallel-In Serial-Out output serialiser
├── Sync_FIFO.v          # Synchronous output FIFO buffer
├── keccak-tb.v          # Top-level testbench (SHA-512, SHAKE-128 test sequences)
├── f_permutation-tb.v   # Permutation-level testbench with golden reference vectors
├── test_keccak.vcd      # Simulation waveform dump (VCD format)
├── some.gtkw            # GTKWave signal configuration file
├── visualise.py         # Python waveform visualisation helper
└── Readme.md            # Project notes
```

---

## Simulation and Verification

The design was verified at two levels:

**Permutation-level (`f_permutation-tb.v`)**: The testbench drives the permutation module with a zero-valued input block and checks the output state against the known Keccak-f[1600] golden reference vector after exactly 24 clock cycles. It also verifies that feeding a second and third block produces the correct successive permutation outputs, ensuring the round counter and state retention logic are correct.

**Top-level (`keccak-tb.v`)**: The system-level testbench exercises the full pipeline in SHA-512 mode (mode = `01`) and SHAKE-128 mode (mode = `10`). It feeds a sequence of 64-bit input words using the `in_valid`/`ack` handshake, asserts `is_last` on the final word, and then drives `gimme` to drain the output FIFO. Intermediate error checks verify that `ack` and `out_valid` behave correctly during initialisation. On successful completion, the simulation prints `"Test Passed!"`.

Waveforms were captured as a VCD file (`test_keccak.vcd`) and inspected using GTKWave with the provided `.gtkw` configuration. A Python helper (`visualise.py`) provides an alternative waveform view.

---

## How to Run

The design can be simulated using any standard Verilog simulator such as **Icarus Verilog** or **ModelSim**.

**Using Icarus Verilog:**

```bash
# Compile all source files with the top-level testbench
iverilog -o keccak_sim \
    keccak_v1.v padder.v SIPO.v f_permutation.v round.v rconst.v PISO.v Sync_FIFO.v \
    keccak-tb.v

# Run the simulation
vvp keccak_sim

# View waveforms in GTKWave
gtkwave test_keccak.vcd some.gtkw
```

To simulate the permutation unit independently:

```bash
iverilog -o fperm_sim f_permutation.v round.v rconst.v f_permutation-tb.v
vvp fperm_sim
```

---

## References

- NIST FIPS 202 — SHA-3 Standard: Permutation-Based Hash and Extendable-Output Functions. https://doi.org/10.6028/NIST.FIPS.202
- Bertoni, G., Daemen, J., Peeters, M., Van Assche, G. — *The Keccak Reference*, Version 3.0. https://keccak.team/files/Keccak-reference-3.0.pdf
- NIST PQC Standards — CRYSTALS-Kyber (FIPS 203) and CRYSTALS-Dilithium (FIPS 204). https://csrc.nist.gov/pqcrypto
- Keccak Team — https://keccak.team
