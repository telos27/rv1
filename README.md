# RV1 - RISC-V CPU Core

A educational RISC-V processor implementation in Verilog, built incrementally from a simple single-cycle design to a pipelined core with extensions.

## Project Goals

- Implement a complete RV32I base integer instruction set
- Progress through increasing complexity: single-cycle → multi-cycle → pipelined
- Add standard extensions (M, A, C) incrementally
- Maintain clean, readable, and synthesizable Verilog code
- Achieve compliance with RISC-V specifications
- Create comprehensive test coverage

## Current Status

**Phase**: Phase 3 - 5-Stage Pipelined Implementation
**Target ISA**: RV32I (32-bit Base Integer)
**Architecture**: 5-stage pipeline (IF → ID → EX → MEM → WB)
**Completion**: ~85% (Stages 3.1-3.5 complete, debugging data forwarding)

**Statistics:**
- **Phase 1**: Single-cycle core ✅ COMPLETE (9 RTL modules, 24/42 compliance tests)
- **Phase 3**: Pipelined core 🔄 IN PROGRESS
  - **15 RTL modules** total (9 Phase 1 + 6 Phase 3 pipeline modules)
  - **7 testbenches** (4 unit + 3 integration)
  - **9 test programs** validated (7 Phase 1 + 2 RAW hazard tests)
  - **47/47 RV32I instructions** supported with hazard handling
  - **24/42 compliance tests PASSED** (57% - matches Phase 1 baseline)

**Recent Achievement (2025-10-10 - Session 3):**
✅ **Critical Control Hazard Bug Fixed!**
- Fixed missing ID/EX pipeline flush on branches/jumps
- All 7 branch/jump tests now pass (beq, bne, blt, bge, bltu, bgeu, jalr)
- Ran full RISC-V compliance test suite
- Pass rate recovered: 45% → 57%
- Core now structurally correct for control flow

See [PHASES.md](PHASES.md) for detailed development roadmap.

## Features Status

### Phase 1: Single-Cycle RV32I ✅ COMPLETE
- [x] Documentation and architecture design
- [x] Basic datapath (PC, RF, ALU, Memory)
- [x] Instruction decoder with all immediate formats
- [x] Control unit with full RV32I support
- [x] All 47 RV32I instructions implemented
- [x] Unit testbenches (ALU, RegFile, Decoder) - 126/126 PASSED
- [x] Integration testbench - 7/7 test programs PASSED
- [x] RISC-V compliance testing - 24/42 PASSED (57%)
- [x] RAW hazard identified (architectural limitation)

### Phase 2: Multi-Cycle (SKIPPED)
- Status: Skipped in favor of direct pipeline implementation
- Rationale: Pipeline better addresses RAW hazard discovered in Phase 1

### Phase 3: 5-Stage Pipeline 🔄 IN PROGRESS (~85% complete)
- [x] **Phase 3.1**: Pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB) ✅
- [x] **Phase 3.2**: Basic pipelined datapath integration ✅
- [x] **Phase 3.3**: Data forwarding (EX-to-EX, MEM-to-EX) ✅
- [x] **Phase 3.4**: Load-use hazard detection with stalling ✅
- [x] **Phase 3.5**: Complete 3-level forwarding (WB-to-ID added) ✅
- [x] **Phase 3.6**: Control hazard bug fixed ✅
  - All branch/jump tests passing
  - 24/42 compliance tests (57% - baseline restored)
- [ ] **Phase 3.7**: Debug data forwarding and load-use hazards
  - Current: Forwarding implemented but not eliminating RAW hazards
  - Target: 40+/42 compliance tests (95%+)

### Phase 4: Extensions
- [ ] M Extension (multiply/divide)
- [ ] CSR support
- [ ] Trap handling
- [ ] A Extension (atomics)
- [ ] Cache implementation
- [ ] C Extension (compressed)

## Directory Structure

```
rv1/
├── docs/               # Design documentation
│   ├── datapaths/      # Datapath diagrams
│   ├── control/        # Control signal tables
│   └── specs/          # Specification documents
├── rtl/                # Verilog RTL source
│   ├── core/           # Core CPU modules
│   │   ├── alu.v
│   │   ├── control.v
│   │   ├── decoder.v
│   │   ├── register_file.v
│   │   └── rv32i_core.v
│   ├── memory/         # Memory subsystem
│   │   ├── instruction_memory.v
│   │   └── data_memory.v
│   └── peripherals/    # I/O peripherals
├── tb/                 # Testbenches
│   ├── unit/           # Unit tests for modules
│   └── integration/    # Full system tests
├── tests/              # Test programs and vectors
│   ├── asm/            # Assembly test programs
│   ├── riscv-tests/    # Official RISC-V tests
│   └── vectors/        # Test vectors
├── sim/                # Simulation files
│   ├── scripts/        # Simulation run scripts
│   └── waves/          # Waveform configurations
├── tools/              # Build and helper scripts
│   ├── assemble.sh     # Assembly to hex
│   └── verify.sh       # Run verification
├── ARCHITECTURE.md     # Detailed architecture documentation
├── CLAUDE.md           # AI assistant context
├── PHASES.md           # Development phases
└── README.md           # This file
```

## Quick Start

### Prerequisites

- Verilog simulator (Verilator, Icarus Verilog, or ModelSim)
- RISC-V GNU toolchain (for assembling test programs)
- Make (for build automation)
- GTKWave (optional, for viewing waveforms)

Check your environment:
```bash
./tools/check_env.sh
```

### Building and Testing

1. **Run unit tests:**
   ```bash
   make test-alu        # Test ALU operations
   make test-regfile    # Test register file
   make test-decoder    # Test instruction decoder
   ```

2. **Assemble test programs:**
   ```bash
   make asm-tests       # Assemble all programs in tests/asm/
   # Or assemble individually:
   ./tools/assemble.sh tests/asm/simple_add.s
   ./tools/assemble.sh tests/asm/fibonacci.s
   ```

3. **Run integration tests:**
   ```bash
   ./tools/run_test.sh simple_add    # Run simple addition test
   ./tools/run_test.sh fibonacci     # Run Fibonacci test
   ./tools/run_all_tests.sh          # Run all tests
   ```

4. **View waveforms:**
   ```bash
   gtkwave sim/waves/alu.vcd         # View ALU test waveform
   gtkwave sim/waves/core.vcd        # View core execution
   ```

### Manual Simulation

Using Icarus Verilog:
```bash
# Compile
iverilog -g2012 -o sim/core.vvp \
  rtl/core/*.v rtl/memory/*.v tb/integration/tb_core.v

# Run
vvp sim/core.vvp

# View waveform
gtkwave sim/waves/core.vcd
```

## Implemented Modules

### Core Components (`rtl/core/`)

**Phase 1: Single-Cycle Modules**
| Module | File | Description | Lines |
|--------|------|-------------|-------|
| **rv32i_core** | `rv32i_core.v` | Single-cycle processor | ~230 |
| **alu** | `alu.v` | 32-bit ALU with 10 operations | ~50 |
| **register_file** | `register_file.v` | 32 GPRs, dual-read, single-write | ~45 |
| **decoder** | `decoder.v` | Instruction decoder & immediate gen | ~60 |
| **control** | `control.v` | Main control unit for all instructions | ~170 |
| **branch_unit** | `branch_unit.v` | Branch condition evaluator | ~35 |
| **pc** | `pc.v` | Program counter with stall support | ~25 |

**Phase 3: Pipeline Modules**
| Module | File | Description | Lines |
|--------|------|-------------|-------|
| **rv32i_core_pipelined** | `rv32i_core_pipelined.v` | 5-stage pipelined processor | ~458 |
| **ifid_register** | `ifid_register.v` | IF/ID pipeline register | ~45 |
| **idex_register** | `idex_register.v` | ID/EX pipeline register | ~125 |
| **exmem_register** | `exmem_register.v` | EX/MEM pipeline register | ~60 |
| **memwb_register** | `memwb_register.v` | MEM/WB pipeline register | ~55 |
| **forwarding_unit** | `forwarding_unit.v` | Data forwarding logic | ~60 |
| **hazard_detection_unit** | `hazard_detection_unit.v` | Load-use hazard detection | ~50 |

### Memory Components (`rtl/memory/`)

| Module | File | Description | Lines |
|--------|------|-------------|-------|
| **instruction_memory** | `instruction_memory.v` | 16KB ROM with hex loading | ~40 |
| **data_memory** | `data_memory.v` | 16KB RAM with byte/word access | ~80 |

### Key Features

**Single-Cycle Core (Phase 1):**
- Single-cycle execution: All instructions complete in one clock cycle
- Harvard architecture: Separate instruction and data memories
- Full RV32I instruction set support (47 instructions)

**Pipelined Core (Phase 3):**
- **5-stage pipeline**: IF → ID → EX → MEM → WB
- **Data forwarding**: EX-to-EX and MEM-to-EX paths eliminate most RAW hazards
- **Hazard detection**: Load-use stalls with automatic bubble insertion
- **Branch handling**: Predict-not-taken with 2-cycle penalty on misprediction
- **Pipeline flush**: Automatic flush on branch/jump mispredictions

**Common Features:**
- Byte-addressable memory: Supports LB, LH, LW, LBU, LHU, SB, SH, SW
- Full immediate support: I, S, B, U, J-type formats with sign extension
- Branch/Jump handling: All 6 branch types + JAL/JALR
- Synthesizable: Clean, FPGA-ready Verilog with no latches

## RISC-V ISA Summary

### RV32I Base Instructions (47 total)

**Integer Computational**
- Register-Register: ADD, SUB, SLL, SLT, SLTU, XOR, SRL, SRA, OR, AND
- Register-Immediate: ADDI, SLTI, SLTIU, XORI, ORI, ANDI, SLLI, SRLI, SRAI
- Upper Immediate: LUI, AUIPC

**Control Transfer**
- Unconditional: JAL, JALR
- Conditional: BEQ, BNE, BLT, BGE, BLTU, BGEU

**Load/Store**
- Loads: LB, LH, LW, LBU, LHU
- Stores: SB, SH, SW

**Memory Ordering**
- FENCE

**System**
- ECALL, EBREAK

## Design Principles

1. **Clarity over Cleverness**: Code should be readable and educational
2. **Incremental Development**: Each phase fully functional before moving on
3. **Test-Driven**: Write tests before or alongside implementation
4. **Spec Compliance**: Follow RISC-V specification exactly
5. **Synthesis-Ready**: Keep FPGA synthesis in mind from the start

## Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Detailed microarchitecture
- [PHASES.md](PHASES.md) - Development roadmap and status
- [CLAUDE.md](CLAUDE.md) - Context for AI assistants
- `docs/` - Additional design documents and diagrams

## Resources

- [RISC-V ISA Specifications](https://riscv.org/technical/specifications/)
- [RISC-V Assembly Programmer's Manual](https://github.com/riscv-non-isa/riscv-asm-manual)
- [RISC-V Tests Repository](https://github.com/riscv/riscv-tests)
- [Computer Organization and Design RISC-V Edition](https://www.elsevier.com/books/computer-organization-and-design-risc-v-edition/patterson/978-0-12-812275-4)

## License

This is an educational project. Feel free to use and modify for learning purposes.

## Contributing

This is a personal learning project, but suggestions and feedback are welcome via issues.

## Acknowledgments

- RISC-V Foundation for the excellent ISA specification
- Open-source RISC-V community for tools and resources
