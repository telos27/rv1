# Phase 3 Implementation Progress

**Project**: RV1 RISC-V Processor - 5-Stage Pipelined Core
**Phase**: 3 - Pipelined Implementation
**Status**: In Progress (Phase 3.1 Complete)
**Start Date**: 2025-10-10
**Last Updated**: 2025-10-10

---

## Overview

Phase 3 aims to implement a classic 5-stage RISC pipeline to eliminate the Read-After-Write (RAW) hazard discovered in Phase 1. This will increase compliance test pass rate from 57% (24/42) to target 95%+ (40+/42).

**Key Goals:**
- Implement 5-stage pipeline (IF, ID, EX, MEM, WB)
- Add data forwarding to resolve RAW hazards
- Implement hazard detection for load-use cases
- Handle control hazards (branches/jumps)
- Achieve 95%+ RISC-V compliance test pass rate

---

## Progress Summary

| Stage | Status | Completion | Tests | Notes |
|-------|--------|------------|-------|-------|
| **3.1: Pipeline Registers** | ✅ Complete | 100% | 7/7 PASSED | All infrastructure ready |
| **3.2: Basic Datapath** | 🔲 Not Started | 0% | - | Next milestone |
| **3.3: Forwarding** | 🔲 Not Started | 0% | - | - |
| **3.4: Hazard Detection** | 🔲 Not Started | 0% | - | - |
| **3.5: Control Hazards** | 🔲 Not Started | 0% | - | - |
| **3.6: Integration Testing** | 🔲 Not Started | 0% | - | - |

**Overall Phase 3 Progress**: ~15% complete

---

## Phase 3.1: Pipeline Registers ✅ COMPLETE

**Completion Date**: 2025-10-10
**Status**: All tasks complete, all tests passing

### Implemented Modules

#### 1. Pipeline Registers (4 modules)

**`ifid_register.v`** - IF/ID Stage Register
- **Lines**: 45 lines
- **Features**:
  - Stall support (for load-use hazards)
  - Flush support (for branch mispredictions)
  - Valid bit tracking
- **Signals**: pc, instruction, valid
- **Test Status**: ✅ PASSED (3/3 tests)

**`idex_register.v`** - ID/EX Stage Register
- **Lines**: 125 lines
- **Features**:
  - Flush support (creates NOP bubbles)
  - 18+ control signals
  - Preserves all decode information
- **Signals**:
  - Data: pc, rs1_data, rs2_data, rs1_addr, rs2_addr, rd_addr, imm
  - Control: alu_control, alu_src, branch, jump, mem_read, mem_write, reg_write, wb_sel
  - Metadata: opcode, funct3, funct7, valid
- **Test Status**: ✅ PASSED (2/2 tests)

**`exmem_register.v`** - EX/MEM Stage Register
- **Lines**: 60 lines
- **Features**:
  - Simple pass-through register
  - No stall/flush needed (handled earlier)
- **Signals**: alu_result, mem_write_data, rd_addr, pc_plus_4, funct3, control signals
- **Test Status**: ✅ PASSED (1/1 test)

**`memwb_register.v`** - MEM/WB Stage Register
- **Lines**: 55 lines
- **Features**:
  - Final stage before write-back
  - Write-back data multiplexing info
- **Signals**: alu_result, mem_read_data, rd_addr, pc_plus_4, control signals
- **Test Status**: ✅ PASSED (1/1 test)

#### 2. Hazard Control Units (2 modules)

**`forwarding_unit.v`** - Data Hazard Resolution
- **Lines**: 60 lines
- **Function**: Detects RAW hazards and generates forwarding control signals
- **Forwarding Paths**:
  - EX-to-EX forwarding (2'b10): Instructions 1 cycle apart
  - MEM-to-EX forwarding (2'b01): Instructions 2 cycles apart
  - Priority: EX/MEM > MEM/WB (most recent data wins)
- **Inputs**: rs1/rs2 addresses from ID/EX, rd addresses and reg_write from EX/MEM and MEM/WB
- **Outputs**: forward_a[1:0], forward_b[1:0]
- **Test Status**: Not yet tested independently (will test in integration)

**`hazard_detection_unit.v`** - Load-Use Hazard Detection
- **Lines**: 50 lines
- **Function**: Detects when load data isn't available yet
- **Detection Logic**:
  - Checks if instruction in EX stage is a load (mem_read=1)
  - Checks if load's rd matches rs1 or rs2 of instruction in ID stage
  - Ignores x0 (zero register)
- **Outputs**: stall_pc, stall_ifid, bubble_idex
- **Effect**: 1-cycle pipeline stall to allow load to complete
- **Test Status**: Not yet tested independently (will test in integration)

#### 3. Testbench

**`tb_pipeline_registers.v`** - Comprehensive Unit Tests
- **Lines**: 460 lines
- **Coverage**: All 4 pipeline registers
- **Tests**:
  1. ✅ IF/ID normal operation
  2. ✅ IF/ID stall (holds values)
  3. ✅ IF/ID flush (inserts NOP)
  4. ✅ ID/EX normal operation
  5. ✅ ID/EX flush (clears control signals)
  6. ✅ EX/MEM normal operation
  7. ✅ MEM/WB normal operation
- **Result**: **7/7 tests PASSED (100%)**
- **Runtime**: <1ms (145ns simulation time)

### Test Results

```
=== Pipeline Register Tests ===

Test 1: IF/ID normal operation
  PASS: Data latched correctly
Test 2: IF/ID stall (should hold values)
  PASS: Values held during stall
Test 3: IF/ID flush (insert NOP)
  PASS: NOP inserted (0x00000013), valid=0
Test 4: ID/EX normal operation
  PASS: ID/EX data latched correctly
Test 5: ID/EX flush (clear control signals)
  PASS: Control signals cleared, valid=0
Test 6: EX/MEM normal operation
  PASS: EX/MEM data latched correctly
Test 7: MEM/WB normal operation
  PASS: MEM/WB data latched correctly

=== Test Summary ===
Total: 7, Pass: 7, Fail: 0

ALL TESTS PASSED!
```

### Deliverables

- ✅ 4 pipeline register modules (285 lines total)
- ✅ 2 hazard control units (110 lines total)
- ✅ Comprehensive testbench (460 lines)
- ✅ All unit tests passing (7/7 PASSED)
- ✅ Documentation in PHASE3_PIPELINE_ARCHITECTURE.md
- ✅ Visual datapath diagrams in PHASE3_DATAPATH_DIAGRAM.md

### Commits

1. **faaf8e5** - Add Phase 3 pipeline architecture documentation
   - 2 files, 1,357 lines of documentation
   - Complete planning for pipeline implementation

2. **a85ca2f** - Implement Phase 3.1: Pipeline registers and hazard control units
   - 7 files, 876 lines of implementation
   - All tests passing

---

## Phase 3.2: Basic Datapath 🔲 NOT STARTED

**Target Start**: Next session
**Estimated Duration**: 2-3 days

### Planned Tasks

1. **Modify PC module** to support stall signal
2. **Create `rv32i_core_pipelined.v`** - Top-level pipelined core
3. **Instantiate all 5 stages**:
   - IF: PC + Instruction Memory
   - ID: Decoder + Control + Register File
   - EX: ALU + Branch Unit (reuse from Phase 1)
   - MEM: Data Memory (reuse from Phase 1)
   - WB: Write-back mux
4. **Connect pipeline registers** between stages
5. **Wire basic datapath** (no forwarding yet)
6. **Initial testing** with simple non-dependent instructions

### Success Criteria

- Pipeline advances instructions through all 5 stages
- Simple programs work (no data hazards)
- PC increments correctly
- Register writes occur at correct time
- Pipeline visualization shows proper flow

### Modules to Reuse from Phase 1

These modules require **no changes**:
- ✅ `alu.v` - ALU operations
- ✅ `decoder.v` - Instruction decode
- ✅ `control.v` - Control signal generation
- ✅ `branch_unit.v` - Branch evaluation
- ✅ `data_memory.v` - Data memory
- ✅ `instruction_memory.v` - Instruction memory

These modules require **modifications**:
- ⚠️ `pc.v` - Add stall input support
- ⚠️ `register_file.v` - Potentially simplify (forwarding handles RAW)

---

## Phase 3.3: Forwarding 🔲 NOT STARTED

**Estimated Duration**: 2-3 days

### Planned Tasks

1. Integrate `forwarding_unit.v` into EX stage
2. Add forwarding muxes for operand A and operand B
3. Connect forwarding paths from EX/MEM and MEM/WB
4. Test EX-to-EX forwarding (back-to-back dependent instructions)
5. Test MEM-to-EX forwarding (2-cycle apart instructions)
6. Run R-type compliance tests (AND, OR, XOR, shifts)

### Expected Results

- RAW hazards eliminated for most cases
- R-type logical operations compliance tests should PASS
- Shift operations compliance tests should PASS
- Estimated: +7 compliance tests passing (from 24 to 31)

---

## Phase 3.4: Load-Use Hazard Detection 🔲 NOT STARTED

**Estimated Duration**: 1-2 days

### Planned Tasks

1. Integrate `hazard_detection_unit.v` into ID stage
2. Connect stall signals to PC and IF/ID register
3. Connect bubble signal to ID/EX register
4. Test load-use sequences
5. Run load/store compliance tests

### Expected Results

- Load-use hazards handled with 1-cycle stall
- No data corruption on load dependencies
- Load/store compliance tests should improve
- Estimated: +5-7 compliance tests passing (from 31 to 36-38)

---

## Phase 3.5: Control Hazards 🔲 NOT STARTED

**Estimated Duration**: 2-3 days

### Planned Tasks

1. Implement branch resolution in EX stage
2. Add PC update logic for branches/jumps
3. Implement pipeline flush (IF/ID and ID/EX)
4. Test branch taken/not-taken scenarios
5. Test JAL/JALR instructions
6. Measure branch penalty (should be 2 cycles)

### Expected Results

- Branches resolve correctly
- Pipeline flushes on misprediction
- Control flow compliance tests continue to PASS
- Branch penalty: 2 cycles (predict not-taken)

---

## Phase 3.6: Integration Testing 🔲 NOT STARTED

**Estimated Duration**: 2-3 days

### Planned Tasks

1. Run all Phase 1 test programs on pipelined core
2. Run full RISC-V compliance test suite
3. Debug any remaining failures
4. Performance analysis (CPI measurement)
5. Generate waveforms for verification
6. Update documentation

### Target Metrics

- **Compliance Tests**: 40+/42 PASSED (95%+)
  - Current: 24/42 (57%)
  - Expected gain: +16-18 tests
- **CPI**: 1.1 - 1.3 cycles per instruction
  - 1.0 for no-hazard instructions
  - +0.1-0.3 for hazards and branches
- **Test Programs**: All 7 custom programs should PASS

### Expected Compliance Breakdown

| Category | Phase 1 | Phase 3 (Target) | Gain |
|----------|---------|------------------|------|
| Arithmetic (ADDI, ADD, SUB, etc.) | ✅ 6/6 | ✅ 6/6 | 0 |
| Logical R-type (AND, OR, XOR) | ❌ 0/3 | ✅ 3/3 | +3 |
| Shifts (SLL, SRL, SRA, etc.) | ❌ 0/4 | ✅ 4/4 | +4 |
| Comparisons (SLT, SLTU) | ✅ 2/2 | ✅ 2/2 | 0 |
| Branches (BEQ, BNE, etc.) | ✅ 6/6 | ✅ 6/6 | 0 |
| Jumps (JAL, JALR) | ✅ 2/2 | ✅ 2/2 | 0 |
| Load/Store (LW, SW, LH, etc.) | ❌ 6/15 | ✅ 13/15 | +7 |
| Upper (LUI, AUIPC) | ✅ 2/2 | ✅ 2/2 | 0 |
| System (FENCE.I, etc.) | ❌ 0/2 | ❌ 0/2 | 0 |
| **Total** | **24/42** | **40/42** | **+16** |

---

## Key Challenges & Solutions

### Challenge 1: RAW Hazard in Phase 1
- **Problem**: Single-cycle core with synchronous register file can't handle back-to-back dependencies
- **Solution**: Pipeline with forwarding eliminates this entirely
- **Impact**: +7 compliance tests (R-type logical, shifts)

### Challenge 2: Load-Use Hazard
- **Problem**: Load data not available in time for next instruction
- **Solution**: 1-cycle stall when hazard detected
- **Impact**: Correct execution, minor CPI increase (~0.1-0.2)

### Challenge 3: Control Hazards
- **Problem**: Branch outcome unknown until EX stage
- **Solution**: Predict not-taken, flush on misprediction
- **Impact**: 2-cycle penalty for taken branches

---

## Next Session Goals

**Phase 3.2: Basic Datapath Integration**

Priority tasks for next session:
1. Review existing Phase 1 single-cycle core (`rv32i_core.v`)
2. Modify `pc.v` to add stall support
3. Create `rv32i_core_pipelined.v` skeleton
4. Instantiate all stages with pipeline registers
5. Wire up basic connections (no forwarding yet)
6. Create initial integration testbench
7. Test with simple non-dependent instruction sequences

**Estimated Time**: 2-3 hours

---

## Documentation Status

- ✅ `PHASE3_PIPELINE_ARCHITECTURE.md` - Complete architecture specification (765 lines)
- ✅ `PHASE3_DATAPATH_DIAGRAM.md` - Visual datapath diagrams (590 lines)
- ✅ `PHASE3_PROGRESS.md` - This progress tracking document
- ✅ `PHASES.md` - Updated with Phase 3.1 completion

---

## File Summary

### New Files Created (Phase 3.1)

**RTL Modules** (7 files, 395 lines):
- `rtl/core/ifid_register.v` (45 lines)
- `rtl/core/idex_register.v` (125 lines)
- `rtl/core/exmem_register.v` (60 lines)
- `rtl/core/memwb_register.v` (55 lines)
- `rtl/core/forwarding_unit.v` (60 lines)
- `rtl/core/hazard_detection_unit.v` (50 lines)

**Testbenches** (1 file, 460 lines):
- `tb/unit/tb_pipeline_registers.v` (460 lines)

**Documentation** (3 files, 1,357 lines):
- `docs/PHASE3_PIPELINE_ARCHITECTURE.md` (765 lines)
- `docs/PHASE3_DATAPATH_DIAGRAM.md` (590 lines)
- `docs/PHASE3_PROGRESS.md` (this file)

**Total New Code**: 2,212 lines

---

## Commit History

| Hash | Date | Description | Files | Lines |
|------|------|-------------|-------|-------|
| faaf8e5 | 2025-10-10 | Add Phase 3 pipeline architecture documentation | 2 | +1357 |
| a85ca2f | 2025-10-10 | Implement Phase 3.1: Pipeline registers and hazard control units | 7 | +876 |

---

**Status**: Phase 3.1 Complete ✅
**Next**: Phase 3.2 - Basic Datapath Integration
**Target Completion**: Phase 3 complete in ~2 weeks
