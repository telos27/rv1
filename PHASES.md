# Development Phases

This document tracks the development progress through each phase of the RV1 RISC-V processor.

## Current Status

**Active Phase**: Phase 1 - Single-Cycle RV32I Core
**Completion**: ~75% (compliance testing complete, fixes needed)
**Next Milestone**: Fix compliance test failures, then performance analysis

**Recent Progress (2025-10-09):**
- ✅ All 9 core RTL modules implemented
- ✅ Unit testbenches created and PASSED (ALU, RegFile, Decoder)
- ✅ Integration testbench completed
- ✅ Comprehensive test coverage expanded from 40% to 85%+
- ✅ Simulation environment configured and operational
- ✅ Unit tests: 126/126 PASSED (100%)
- ✅ Integration tests: 7/7 PASSED (100%)
  - simple_add ✓
  - fibonacci ✓
  - load_store ✓
  - logic_ops ✓
  - shift_ops ✓
  - branch_test ✓
  - jump_test ✓
- ✅ Load/store issue FIXED (was address out-of-bounds, not timing)
- ✅ **RISC-V Compliance Tests: 24/42 PASSED (57%)**
  - Official riscv-tests RV32UI suite executed
  - Identified 3 main issue areas: right shifts, R-type logical ops, load/store edge cases
  - See COMPLIANCE_RESULTS.md for detailed analysis

---

## Phase 0: Documentation and Setup ✅

**Goal**: Establish project structure and documentation

**Status**: COMPLETED (2025-10-09)

### Checklist
- [x] Create CLAUDE.md (AI context)
- [x] Create README.md (project overview)
- [x] Create ARCHITECTURE.md (design details)
- [x] Create PHASES.md (this file)
- [x] Create directory structure
- [x] Set up simulation environment
- [x] Create Makefile/build scripts
- [x] Document coding style guide

### Deliverables
1. ✅ Complete documentation set
2. ✅ Directory structure with all folders
3. ✅ Build system (Makefile)
4. ✅ Simulation scripts (check_env.sh, run_test.sh, etc.)

**Completion Date**: 2025-10-09

---

## Phase 1: Single-Cycle RV32I Core

**Goal**: Implement a complete single-cycle processor supporting all RV32I instructions

**Status**: IN PROGRESS (~75%)

**Start Date**: 2025-10-09
**Last Updated**: 2025-10-09
**Estimated Completion**: 2-3 days (pending compliance test fixes)

### Stage 1.1: Basic Infrastructure ✅
**Status**: COMPLETED

#### Tasks
- [x] Implement Program Counter (PC) module
- [x] Implement Instruction Memory
- [x] Implement Register File
- [x] Write unit tests for each module
- [x] Verify basic functionality

#### Success Criteria
- ✅ PC increments correctly with stall support
- ✅ Instruction memory loads from hex file
- ✅ Register file: x0 is always 0, read/write works
- ✅ All unit tests pass (75/75 register file tests PASSED)

**Implementation Files:**
- `rtl/core/pc.v` (25 lines)
- `rtl/memory/instruction_memory.v` (40 lines)
- `rtl/core/register_file.v` (45 lines)
- `tb/unit/tb_register_file.v` (testbench)

### Stage 1.2: ALU and Immediate Generation ✅
**Status**: COMPLETED

#### Tasks
- [x] Implement ALU with all operations
- [x] Implement immediate generator (integrated in decoder)
- [x] Implement instruction decoder
- [x] Write comprehensive ALU tests
- [x] Test all immediate formats

#### Success Criteria
- ✅ ALU performs all 10 operations correctly (40/40 tests PASSED)
- ✅ Immediate generation for I, S, B, U, J formats (11/11 tests PASSED)
- ✅ Decoder extracts all instruction fields
- ✅ Flag generation (zero, less_than, less_than_unsigned) works

**Implementation Files:**
- `rtl/core/alu.v` (50 lines)
- `rtl/core/decoder.v` (60 lines)
- `tb/unit/tb_alu.v` (60+ test cases)
- `tb/unit/tb_decoder.v` (immediate format tests)

### Stage 1.3: Control Unit ✅
**Status**: COMPLETED

#### Tasks
- [x] Implement control signal generation
- [x] Create control signal truth table (in code)
- [x] Map all RV32I opcodes
- [x] Test control signals for each instruction type

#### Success Criteria
- ✅ Correct control signals for all instruction types
- ✅ R, I, S, B, U, J types handled
- ✅ Special cases (JALR, FENCE, ECALL/EBREAK) handled

**Implementation Files:**
- `rtl/core/control.v` (170 lines, full RV32I support)

### Stage 1.4: Memory System ✅
**Status**: COMPLETED

#### Tasks
- [x] Implement data memory with byte/halfword/word access
- [x] Add support for signed/unsigned loads
- [x] Implement branch unit
- [x] Test memory alignment (via funct3)
- [ ] Test load/store variants (awaiting simulation)

#### Success Criteria
- ✅ LB, LH, LW, LBU, LHU implemented
- ✅ SB, SH, SW implemented
- ✅ Proper sign extension logic
- ✅ Branch conditions (BEQ, BNE, BLT, BGE, BLTU, BGEU) evaluated correctly

**Implementation Files:**
- `rtl/memory/data_memory.v` (80 lines, full byte/halfword/word support)
- `rtl/core/branch_unit.v` (35 lines, all 6 branch types)

### Stage 1.5: Top-Level Integration ✅
**Status**: COMPLETED

#### Tasks
- [x] Create top-level rv32i_core module
- [x] Wire all components together
- [x] Implement PC calculation logic
- [x] Create comprehensive testbench
- [x] Test with simple programs

#### Success Criteria
- ✅ All components integrated in single-cycle datapath
- ✅ Test programs written (simple_add, fibonacci, load_store)
- ✅ PC jumps and branches implemented
- ⏳ No timing violations (pending simulation)

**Implementation Files:**
- `rtl/core/rv32i_core.v` (~200 lines, complete integration)
- `tb/integration/tb_core.v` (integration testbench)
- `tests/asm/simple_add.s`
- `tests/asm/fibonacci.s`
- `tests/asm/load_store.s`

### Stage 1.6: Instruction Testing
**Status**: COMPLETED

#### Tasks
- [x] Implement all integer computational instructions
- [x] Implement all load/store instructions
- [x] Implement all branch instructions
- [x] Implement JAL and JALR
- [x] Implement LUI and AUIPC
- [x] Run unit tests with simulation
- [x] Verify each instruction individually

#### Test Programs Created
1. ✅ **simple_add.s**: Basic ADD, ADDI operations - PASSED (result = 15)
2. ✅ **fibonacci.s**: Tests loops, branches, arithmetic - PASSED (fib(10) = 55)
3. ✅ **load_store.s**: Tests LW, LH, LB, SW, SH, SB - PASSED (x10=42, x11=100, x12=-1)
4. ✅ **logic_ops.s**: Tests AND, OR, XOR, ANDI, ORI, XORI - PASSED (61 cycles)
5. ✅ **shift_ops.s**: Tests SLL, SRL, SRA, SLLI, SRLI, SRAI - PASSED (56 cycles)
6. ✅ **branch_test.s**: Tests all 6 branch types (BEQ, BNE, BLT, BGE, BLTU, BGEU) - PASSED (70 cycles)
7. ✅ **jump_test.s**: Tests JAL, JALR, LUI, AUIPC - PASSED (49 cycles)

#### Success Criteria
- ✅ All 47 RV32I instructions implemented in hardware
- ✅ Unit tests verify core functionality (126/126 PASSED)
- ✅ Integration tests verify instruction execution (7/7 PASSED)
- ✅ Edge cases tested (overflow, zero, signed/unsigned comparisons, etc.)

### Stage 1.7: Integration Testing
**Status**: IN PROGRESS

#### Tasks
- [x] Create Fibonacci test program
- [x] Run Fibonacci sequence - PASSED (55 in 65 cycles)
- [x] Run simple_add test - PASSED (15 in 5 cycles)
- [x] Set up simulation environment (Icarus Verilog + RISC-V toolchain)
- [x] Debug load/store address issue - FIXED
- [x] Run RISC-V compliance tests (RV32UI) - 24/42 PASSED (57%)
- [ ] Fix compliance test failures (target: 90%+)
- [ ] Run bubble sort (optional)
- [ ] Run factorial calculation (optional)
- [ ] Performance analysis

#### Test Programs
```
1. ✅ simple_add.s    - PASSED (basic arithmetic)
2. ✅ fibonacci.s     - PASSED (loops and conditionals)
3. ✅ load_store.s    - PASSED (memory operations)
4. ✅ logic_ops.s     - PASSED (logical operations)
5. ✅ shift_ops.s     - PASSED (shift operations)
6. ✅ branch_test.s   - PASSED (all branch types)
7. ✅ jump_test.s     - PASSED (jumps and upper immediates)
8. ⏳ bubblesort.s    - Not yet created (optional)
9. ⏳ factorial.s     - Not yet created (optional)
```

#### Success Criteria
- ✅ Basic test programs produce correct results (7/7)
- ⚠️ RISC-V compliance tests pass (at least 90%) - **24/42 (57%) - NEEDS FIXES**
  - ✅ Branches, jumps, arithmetic, comparisons passing
  - ❌ Right shifts, R-type logical ops, load/store edge cases failing
  - See COMPLIANCE_RESULTS.md for detailed analysis
- ✅ All memory operations verified (word, halfword, byte loads/stores - in custom tests)
- ✅ All logical operations verified (AND, OR, XOR and immediate variants - in custom tests)
- ⚠️ Shift operations verified (left shifts work, right shifts have issues)
- ✅ All branch types verified (signed and unsigned comparisons)
- ✅ Jump operations verified (JAL, JALR, LUI, AUIPC)
- ✅ Waveforms generated and available for analysis

### Phase 1 Deliverables

**Completed:**
1. ✅ Complete single-cycle core (9 modules: ALU, RegFile, PC, Decoder, Control, Branch Unit, IMem, DMem, Core)
2. ✅ Unit testbenches (ALU, Register File, Decoder)
3. ✅ Integration testbench (tb_core.v) with compliance test support
4. ✅ Comprehensive test programs (7 programs covering 85%+ of instructions)
   - simple_add, fibonacci, load_store
   - logic_ops, shift_ops, branch_test, jump_test
5. ✅ Build system (Makefile, shell scripts)
6. ✅ Simulation environment setup (Icarus Verilog + RISC-V toolchain)
7. ✅ Unit test verification (126/126 tests PASSED)
8. ✅ Integration test verification (7/7 tests PASSED)
9. ✅ Load/store address issue FIXED (was out-of-bounds access)
10. ✅ Instruction coverage expanded to 85%+
11. ✅ RISC-V compliance tests executed (24/42 PASSED, 57%)
12. ✅ Compliance test infrastructure (conversion scripts, automation)
13. ✅ Memory expanded to 16KB (for compliance tests)
14. ✅ Address masking for 0x80000000 base addresses

**Pending:**
15. ⏳ Fix compliance test failures (target: 90%+)
    - Right shift operations (SRA, SRAI, SRL, SRLI)
    - R-type logical ops (AND, OR, XOR)
    - Load/store edge cases
16. ⏳ Timing analysis report
13. ⏳ Documentation of any spec deviations
14. ⏳ Optional: Additional complex programs (bubblesort, factorial, gcd)

**Target Completion**: 2-3 days (pending compliance test fixes)

**Implementation Summary (Updated 2025-10-09):**
- **Total RTL lines**: ~705 lines of Verilog
- **Total testbench lines**: ~450 lines
- **Total test programs**: 7 custom assembly programs + 42 compliance tests
- **Instructions supported**: 47/47 RV32I base instructions
- **Instructions tested in integration**: ~40/47 (85%+)
- **Test coverage**:
  - **Unit tests**: 126/126 PASSED (100%)
  - **Custom integration tests**: 7/7 PASSED (100%)
  - **RISC-V compliance tests**: 24/42 PASSED (57%)
  - **Overall**: 157/175 tests passed (90%)
- **Bugs fixed**: 7 (toolchain, testbench, assembly, address bounds)
- **Known issues**: Right shifts, R-type logical ops, load/store edge cases

---

## Phase 2: Multi-Cycle Implementation

**Goal**: Convert single-cycle to multi-cycle for resource optimization

**Status**: NOT STARTED

**Estimated Duration**: 2 weeks

### Stage 2.1: FSM Design
**Status**: NOT STARTED

#### Tasks
- [ ] Design 5-state FSM (Fetch, Decode, Execute, Memory, Writeback)
- [ ] Create state transition diagram
- [ ] Implement FSM in Verilog
- [ ] Add internal state registers (IR, MDR, A, B, ALUOut)

#### Success Criteria
- FSM transitions correctly
- All states reachable
- State encoding documented

### Stage 2.2: Shared Memory Interface
**Status**: NOT STARTED

#### Tasks
- [ ] Combine instruction and data memory
- [ ] Add memory arbiter
- [ ] Implement address multiplexing
- [ ] Test memory conflicts

#### Success Criteria
- Single memory accessed in Fetch and Memory states
- No conflicts
- Memory timing correct

### Stage 2.3: Multi-Cycle Control
**Status**: NOT STARTED

#### Tasks
- [ ] Implement state-dependent control signals
- [ ] Update control unit for multi-cycle
- [ ] Add cycle counters
- [ ] Test each state independently

#### Success Criteria
- Control signals correct in each state
- Different instructions take appropriate cycles
- CPI measured and documented

### Stage 2.4: Testing and Verification
**Status**: NOT STARTED

#### Tasks
- [ ] Port single-cycle tests to multi-cycle
- [ ] Verify identical functional behavior
- [ ] Compare timing and resource usage
- [ ] Run compliance tests

#### Success Criteria
- Same programs work on both implementations
- Resource usage reduced (fewer muxes, etc.)
- Cycle counts match expectations

### Phase 2 Deliverables
1. Multi-cycle core implementation
2. FSM documentation
3. Cycle count analysis
4. Resource comparison report

**Target Completion**: TBD

---

## Phase 3: 5-Stage Pipeline

**Goal**: Implement classic RISC pipeline with hazard handling

**Status**: NOT STARTED

**Estimated Duration**: 3-4 weeks

### Stage 3.1: Basic Pipeline Structure
**Status**: NOT STARTED

#### Tasks
- [ ] Create IF/ID pipeline register
- [ ] Create ID/EX pipeline register
- [ ] Create EX/MEM pipeline register
- [ ] Create MEM/WB pipeline register
- [ ] Update all modules for pipelined operation

#### Success Criteria
- Pipeline registers update correctly
- Basic instruction flow through pipeline
- No hazard handling yet (will fail on dependencies)

### Stage 3.2: Forwarding Logic
**Status**: NOT STARTED

#### Tasks
- [ ] Implement forwarding detection logic
- [ ] Add forwarding muxes to EX stage
- [ ] Implement EX-to-EX forwarding
- [ ] Implement MEM-to-EX forwarding
- [ ] Test with RAW hazard cases

#### Success Criteria
- Back-to-back dependent instructions work
- Forwarding paths tested
- No unnecessary stalls for resolved hazards

### Stage 3.3: Load-Use Hazard Detection
**Status**: NOT STARTED

#### Tasks
- [ ] Implement hazard detection unit
- [ ] Add pipeline stall logic
- [ ] Insert bubbles (nops) when necessary
- [ ] Test load-use cases

#### Success Criteria
- Load followed by dependent instruction stalls 1 cycle
- Pipeline recovers after stall
- No data corruption

### Stage 3.4: Branch Handling
**Status**: NOT STARTED

#### Tasks
- [ ] Implement branch resolution in EX stage
- [ ] Add pipeline flush logic
- [ ] Implement predict-not-taken
- [ ] Calculate branch penalties

#### Success Criteria
- Branches resolve correctly
- Pipeline flushes on taken branches
- Branch delay measured (2-3 cycles)

### Stage 3.5: Jump Handling
**Status**: NOT STARTED

#### Tasks
- [ ] Handle JAL in ID stage (early)
- [ ] Handle JALR (must wait for register read)
- [ ] Optimize to reduce jump penalties
- [ ] Test return address generation

#### Success Criteria
- JAL has minimal penalty
- JALR handled correctly
- Return addresses correct

### Stage 3.6: Pipeline Testing
**Status**: NOT STARTED

#### Tasks
- [ ] Test all hazard scenarios
- [ ] Run previous test programs
- [ ] Measure CPI for different code patterns
- [ ] Verify against compliance tests
- [ ] Performance analysis

#### Test Scenarios
1. **No hazards**: Independent instructions
2. **RAW hazards**: Back-to-back dependencies
3. **Load-use**: Load followed by use
4. **Branches**: Taken and not-taken
5. **Jumps**: JAL and JALR

#### Success Criteria
- CPI between 1.0-1.5
- All programs functionally correct
- Pipeline visualization clear
- Compliance tests pass

### Stage 3.7: Branch Prediction (Optional)
**Status**: NOT STARTED

#### Tasks
- [ ] Implement 1-bit predictor
- [ ] Implement 2-bit saturating counter
- [ ] Add BTB (Branch Target Buffer)
- [ ] Measure prediction accuracy

#### Success Criteria
- Prediction accuracy > 80% on typical code
- CPI improvement measured
- Misprediction penalty handled

### Phase 3 Deliverables
1. Complete 5-stage pipelined core
2. Hazard detection and forwarding logic
3. Pipeline visualization tools
4. Performance analysis report
5. CPI breakdown by hazard type

**Target Completion**: TBD

---

## Phase 4: Extensions and Advanced Features

**Goal**: Add ISA extensions and performance features

**Status**: NOT STARTED

**Estimated Duration**: 4-6 weeks (spread across sub-phases)

### Stage 4.1: M Extension (Multiply/Divide)
**Status**: NOT STARTED

#### Tasks
- [ ] Design multiplier (iterative or booth)
- [ ] Design divider (restoring or non-restoring)
- [ ] Implement MUL, MULH, MULHSU, MULHU
- [ ] Implement DIV, DIVU, REM, REMU
- [ ] Multi-cycle execution unit
- [ ] Pipeline stalling for M instructions

#### Success Criteria
- All 8 M instructions work correctly
- Edge cases (divide by zero, overflow) handled
- Performance acceptable (< 34 cycles for div)
- Compliance tests pass

### Stage 4.2: CSR Support
**Status**: NOT STARTED

#### Tasks
- [ ] Implement CSR register file
- [ ] Implement CSRRW, CSRRS, CSRRC
- [ ] Implement CSRRWI, CSRRSI, CSRRCI
- [ ] Add key CSRs (mstatus, mie, mtvec, etc.)
- [ ] Privilege mode tracking

#### Success Criteria
- CSR instructions work correctly
- CSR side effects handled
- Read/write permissions enforced

### Stage 4.3: Trap Handling
**Status**: NOT STARTED

#### Tasks
- [ ] Implement exception detection
- [ ] Implement trap vector logic
- [ ] Save/restore PC (mepc)
- [ ] Implement MRET instruction
- [ ] Handle synchronous exceptions
- [ ] Handle interrupts (timer, external)

#### Exceptions to Handle
- Illegal instruction
- Instruction address misaligned
- Load address misaligned
- Store address misaligned
- ECALL
- EBREAK

#### Success Criteria
- Exceptions trigger correctly
- Trap handler invoked
- Return from trap works
- Nested traps handled

### Stage 4.4: A Extension (Atomics)
**Status**: NOT STARTED

#### Tasks
- [ ] Implement LR.W (load reserved)
- [ ] Implement SC.W (store conditional)
- [ ] Implement AMO instructions (AMOADD, AMOSWAP, etc.)
- [ ] Add reservation station
- [ ] Test atomic sequences

#### Success Criteria
- LR/SC primitives work
- AMO instructions atomic
- Useful for synchronization

### Stage 4.5: Caching
**Status**: NOT STARTED

#### Tasks
- [ ] Design I-cache (direct-mapped)
- [ ] Implement cache controller
- [ ] Add miss handling
- [ ] Implement D-cache (set-associative)
- [ ] Cache coherency (if needed)

#### Success Criteria
- Cache hit/miss detection
- Improved performance on repeated code
- Miss penalty measured

### Stage 4.6: C Extension (Compressed)
**Status**: NOT STARTED

#### Tasks
- [ ] Implement 16-bit instruction decoder
- [ ] Expand compressed to 32-bit internally
- [ ] Handle PC increment (2 or 4 bytes)
- [ ] Test compressed programs

#### Success Criteria
- All compressed instructions expand correctly
- Mixed 16/32-bit code works
- Code density improvement measured

### Stage 4.7: Advanced Branch Prediction
**Status**: NOT STARTED

#### Tasks
- [ ] Implement gshare predictor
- [ ] Implement return address stack
- [ ] Measure branch prediction accuracy
- [ ] Tune predictor parameters

#### Success Criteria
- Prediction accuracy > 90%
- Return prediction near 100%
- CPI improvement measured

### Phase 4 Deliverables
1. M extension implementation
2. CSR and trap handling
3. Optional: A, C extensions
4. Optional: Cache hierarchy
5. Performance comparison report

**Target Completion**: TBD

---

## Phase 5: Advanced Topics (Future)

**Goal**: Research-level features and optimizations

**Status**: NOT STARTED

### Potential Features
- [ ] Out-of-order execution (Tomasulo)
- [ ] Superscalar (2-issue)
- [ ] Virtual memory (MMU with TLB)
- [ ] Floating-point unit (F/D extensions)
- [ ] Debug module (JTAG interface)
- [ ] Performance counters
- [ ] Power management
- [ ] FPGA synthesis and testing
- [ ] ASIC backend flow

---

## Testing Strategy

### Unit Tests
Each module tested independently with:
- Directed tests (specific scenarios)
- Corner cases
- Error conditions

### Integration Tests
- Instruction-level tests
- Small programs
- RISC-V compliance suite

### Verification Approach
1. **Simulation**: Icarus/Verilator
2. **Waveform analysis**: GTKWave
3. **Coverage**: Functional coverage tracking
4. **Comparison**: Against golden model (Spike/QEMU)

### Compliance Testing
Use official RISC-V tests:
```
riscv-tests/isa/rv32ui-p-*    # RV32I user-level tests
riscv-tests/isa/rv32um-p-*    # RV32M tests
riscv-tests/isa/rv32ua-p-*    # RV32A tests
```

---

## Metrics to Track

### Functional
- [ ] Instructions implemented (count/47 for RV32I)
- [ ] Compliance tests passed (percentage)
- [ ] Known bugs (count)

### Performance
- [ ] Clock frequency (MHz)
- [ ] CPI (cycles per instruction)
- [ ] IPC (instructions per cycle)
- [ ] Branch prediction accuracy (%)
- [ ] Cache hit rate (%)

### Resource
- [ ] LUTs used (FPGA)
- [ ] Registers/FFs
- [ ] Block RAM
- [ ] Critical path delay

---

## Risk Management

### Technical Risks
1. **Timing closure**: May not meet target frequency
   - Mitigation: Pipeline critical paths early

2. **Verification gaps**: Bugs in corner cases
   - Mitigation: Comprehensive test suite

3. **Spec compliance**: Misunderstanding ISA spec
   - Mitigation: Read spec carefully, use official tests

### Schedule Risks
1. **Scope creep**: Adding features beyond plan
   - Mitigation: Stick to phase goals

2. **Debug time**: Underestimating bug fixing
   - Mitigation: Allocate 30% time for debug

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2025-10-09 | Initial phase planning |

---

## Notes

- Each phase should be fully functional before moving to next
- Document all design decisions
- Keep test infrastructure up to date
- Regular commits with clear messages
- Review RISC-V spec frequently
