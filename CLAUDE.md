# CLAUDE.md - AI Assistant Context

## Project Overview
This project implements a RISC-V CPU core in Verilog, starting from a simple single-cycle design and progressively adding features to reach a complete pipelined processor with extensions.

## Current Status
**Phase**: Planning and Documentation
**Target**: RV32I base ISA initially, then extensions

## Development Philosophy
- **Incremental**: Each phase builds on the previous one
- **Testable**: Every feature must have corresponding tests
- **Educational**: Code should be clear and well-commented
- **Compliance**: Verify against official RISC-V tests

## Project Structure
```
rv1/
├── docs/           # Design documents and specifications
├── rtl/            # Verilog source files
│   ├── core/       # CPU core modules
│   ├── memory/     # Memory components
│   └── peripherals/# I/O and peripherals
├── tb/             # Testbenches
├── tests/          # Test programs and vectors
├── sim/            # Simulation scripts and results
└── tools/          # Helper scripts
```

## Design Constraints
- **HDL**: SystemVerilog subset (Verilog-2001 compatible)
- **Target**: FPGA-friendly design (no technology-specific cells initially)
- **Simulation**: Verilator for fast simulation, optional ModelSim/Icarus
- **Word Size**: 32-bit (RV32I)
- **Endianness**: Little-endian (RISC-V standard)

## Key Design Decisions

### Phase 1: Single-Cycle
- Harvard architecture (separate I/D memory for simplicity)
- Synchronous register file (write on posedge)
- Byte-addressable memory (word-aligned for phase 1)
- No interrupts/exceptions initially

### Phase 2: Multi-Cycle
- State machine based control
- Shared memory interface
- Reduced critical path

### Phase 3: Pipelined
- Classic 5-stage pipeline
- Forwarding for data hazards
- Stalling and flushing for control hazards
- Pipeline registers between stages

### Phase 4: Extensions
- M extension (multiply/divide)
- CSR registers and privilege modes
- Trap handling
- Optional: A, C extensions, caching, branch prediction

## Naming Conventions

### Files
- Modules: `snake_case.v` (e.g., `alu.v`, `register_file.v`)
- Testbenches: `tb_<module>.v` (e.g., `tb_alu.v`)
- Top level: `rv32i_core.v`

### Signals
- Active-low signals: `_n` suffix (e.g., `reset_n`)
- Registered outputs: `_r` suffix (e.g., `data_out_r`)
- Next-state: `_next` suffix (e.g., `state_next`)
- Combinational: descriptive names (e.g., `alu_result`)

### Parameters
- UPPERCASE with underscores (e.g., `DATA_WIDTH`, `ADDR_WIDTH`)

## Testing Strategy
1. **Unit Tests**: Each module tested independently
2. **Instruction Tests**: Each instruction verified with known results
3. **Compliance Tests**: RISC-V official test suite
4. **Program Tests**: Small assembly programs (Fibonacci, sorting, etc.)
5. **Random Tests**: Constrained random instruction sequences

## Common RISC-V Instruction Formats
```
R-type: funct7[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
I-type: imm[31:20] | rs1[19:15] | funct3[14:12] | rd[11:7] | opcode[6:0]
S-type: imm[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
B-type: imm[31:25] | rs2[24:20] | rs1[19:15] | funct3[14:12] | imm[11:7] | opcode[6:0]
U-type: imm[31:12] | rd[11:7] | opcode[6:0]
J-type: imm[31:12] | rd[11:7] | opcode[6:0]
```

## Useful References
- RISC-V ISA Spec: https://riscv.org/technical/specifications/
- RV32I Base: Volume 1, Chapter 2
- Unprivileged ISA: https://github.com/riscv/riscv-isa-manual
- Test Suite: https://github.com/riscv/riscv-tests
- Compliance: https://github.com/riscv/riscv-compliance

## When Assisting

### Before Making Changes
1. Check current phase in PHASES.md
2. Review ARCHITECTURE.md for design constraints
3. Verify against RISC-V spec

### Code Style
- Use 2-space indentation
- Keep lines under 100 characters
- Comment complex logic
- Use meaningful signal names
- Group related signals in modules

### Adding Features
1. Update PHASES.md with status
2. Design the feature (document in ARCHITECTURE.md)
3. Implement the Verilog module
4. Write testbench
5. Verify with tests
6. Update documentation

### Debug Approach
1. Check waveforms first
2. Verify control signals
3. Check instruction decode
4. Trace data path
5. Look for timing issues

## Current Priorities
1. Complete documentation
2. Set up directory structure
3. Implement Phase 1 single-cycle core
4. Create comprehensive testbenches
5. Verify with basic programs

## Notes for Future Development
- Keep reset consistent (async vs sync)
- Plan for synthesis early (avoid unsynthesizable constructs)
- Consider formal verification for critical paths
- Document all assumptions about memory timing
- Plan interrupt handling architecture from early stages
