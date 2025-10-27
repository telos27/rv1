# Refactoring Plan

**Date**: 2025-10-26
**Status**: In Progress - Phase 1 (Task 1.1 Complete ✅)
**Purpose**: Document code quality improvements and technical debt reduction

## Executive Summary

The RV1 RISC-V processor has achieved 100% compliance with official tests and implements a complete RV32IMAFDC instruction set with privilege architecture. As the codebase has grown to ~13K lines of RTL, several refactoring opportunities have emerged to improve maintainability, readability, and extensibility.

This document outlines refactoring tasks prioritized by impact and risk.

## Codebase Statistics (Current State)

### RTL Module Sizes
| Module | Lines | Complexity | Notes |
|--------|-------|------------|-------|
| `rv32i_core_pipelined.v` | 2,468 | **High** | Main integration, 33 always blocks |
| `fp_converter.v` | 878 | Medium | FP format conversion |
| `fp_fma.v` | 647 | Medium | Fused multiply-add |
| `csr_file.v` | 632 | Medium | CSR register file |
| `fp_adder.v` | 614 | Medium | FP addition |
| `fp_divider.v` | 567 | Medium | FP division |
| `fpu.v` | 566 | Medium | FPU top-level |
| `control.v` | 557 | Medium | Control signal generation |
| `rvc_decoder.v` | 525 | Medium | Compressed instruction decoder |

### Code Duplication Issues Identified

1. **CSR Constants**: MSTATUS bit positions duplicated in 3 files
   - `csr_file.v` (lines 127-135)
   - `rv32i_core_pipelined.v` (lines 1747-1759)
   - `hazard_detection_unit.v`

2. **CSR Addresses**: CSR address definitions in multiple modules
   - `csr_file.v`
   - `rv32i_core_pipelined.v` (lines 1758-1759)
   - `hazard_detection_unit.v`

3. **Pipeline Registers**: 4 similar modules with repeated patterns
   - `ifid_register.v`
   - `idex_register.v` (370 lines)
   - `exmem_register.v`
   - `memwb_register.v`

---

## Priority 1: High Impact, Low Risk 🟢

### Task 1.1: Extract CSR and Privilege Constants to Shared Header

**Problem:**
- MSTATUS bit positions defined identically in 3 files
- CSR addresses scattered across modules
- Privilege mode encodings duplicated
- Any change requires updating multiple files

**Current Duplication:**
```verilog
// In csr_file.v:
localparam MSTATUS_SIE_BIT  = 1;
localparam MSTATUS_MIE_BIT  = 3;
localparam MSTATUS_SPIE_BIT = 5;
// ... etc

// In rv32i_core_pipelined.v:
localparam MSTATUS_MIE_BIT  = 3;  // DUPLICATED
localparam MSTATUS_SIE_BIT  = 1;  // DUPLICATED
// ... etc
```

**Solution:**
Create `rtl/config/rv_csr_defines.vh` with:
- MSTATUS/SSTATUS bit positions
- All CSR addresses (0x000-0xFFF)
- Privilege mode encodings (U=00, S=01, M=11)
- Exception/interrupt cause codes
- WARL field masks

**Implementation Steps:**
1. Create `rtl/config/rv_csr_defines.vh`
2. Move all CSR-related constants to header
3. Add `include "config/rv_csr_defines.vh"` to affected modules
4. Remove duplicate definitions
5. Run full regression tests to verify

**Files to Modify:**
- NEW: `rtl/config/rv_csr_defines.vh`
- `rtl/core/csr_file.v`
- `rtl/core/rv32i_core_pipelined.v`
- `rtl/core/hazard_detection_unit.v`
- `rtl/core/exception_unit.v` (if needed)

**Estimated Effort:** 1 hour
**Lines Saved:** 30-40 lines
**Risk:** Very Low (just moving constants)
**Testing:** Quick regression (`make test-quick`)

**Benefits:**
- Single source of truth for CSR definitions
- Easier to add new CSRs
- Reduced chance of inconsistencies
- Better alignment with RISC-V spec structure

---

### Task 1.2: Split Main Core File into Stage-Based Modules

**Problem:**
- `rv32i_core_pipelined.v` is 2,468 lines - difficult to navigate
- 33 always blocks mixed together
- 5 pipeline stages intermixed with forwarding logic
- Hard to understand data flow
- Difficult to review changes

**Current Structure:**
```
rv32i_core_pipelined.v (2,468 lines)
├── Pipeline Control Signals (lines 23-52)
├── IF Stage Signals (lines 53-65)
├── IF/ID Register Outputs (lines 66-73)
├── ID Stage Signals (lines 74-154)
├── ID/EX Register Outputs (lines 155-212)
├── EX Stage Signals (lines 213-329)
├── EX/MEM Register Outputs (lines 330-370)
├── MEM Stage Signals (lines 371-403)
├── MEM/WB Register Outputs (lines 404-430)
├── CSR and Exception Signals (lines 431-539)
├── WB Stage Signals (lines 540-545)
├── Privilege Mode Tracking (lines 588-715)
├── ID Stage Logic (lines 716-1182)
├── EX Stage Logic (lines 1183-1525)
├── CSR File Instantiation (lines 1526-1621)
├── Exception Unit (lines 1622-1671)
├── FPU Instantiation (lines 1672-1739)
├── CSR MRET/SRET Forwarding (lines 1740-1909)
├── Privilege Mode Forwarding (lines 1910-1957)
└── Pipeline Register Instantiations (lines 1958-2468)
```

**Proposed Structure:**
```
rtl/core/
├── rv_core_pipelined.v           (main integration, ~600-800 lines)
│   └── Top-level module, stage instantiations, global signals
├── rv_core_if_stage.v             (~200-300 lines)
│   ├── PC logic
│   ├── Instruction memory interface
│   └── Compressed instruction detection
├── rv_core_id_stage.v             (~300-400 lines)
│   ├── Decoder instantiation
│   ├── Register file reads
│   ├── Immediate generation
│   └── Control signal generation
├── rv_core_ex_stage.v             (~300-400 lines)
│   ├── ALU instantiation
│   ├── Branch unit
│   ├── Mul/Div unit
│   └── Data forwarding muxes
├── rv_core_mem_stage.v            (~200-300 lines)
│   ├── Data memory interface
│   ├── MMU/TLB
│   └── Atomic operations
├── rv_core_wb_stage.v             (~100-150 lines)
│   └── Write-back data muxing
├── rv_core_csr_forward.v          (~200-250 lines)
│   ├── CSR forwarding logic (MRET/SRET)
│   ├── MSTATUS computation functions
│   └── CSR hazard detection
└── rv_core_priv_forward.v         (~150-200 lines)
    ├── Privilege mode forwarding
    ├── Privilege mode state machine
    └── Trap target computation
```

**Key Design Principles:**
1. Each stage module handles its own combinational logic
2. Pipeline registers remain as separate modules (ifid_register.v, etc.)
3. Main core instantiates stages and connects pipeline registers
4. Forwarding paths handled by dedicated modules
5. Clear hierarchical structure matching pipeline diagrams

**Interface Example:**
```verilog
module rv_core_if_stage #(
  parameter XLEN = 32
) (
  input  wire             clk,
  input  wire             reset_n,

  // Control inputs
  input  wire             stall,
  input  wire             branch_taken,
  input  wire [XLEN-1:0]  branch_target,
  input  wire             trap_taken,
  input  wire [XLEN-1:0]  trap_target,

  // Instruction memory interface
  output wire [XLEN-1:0]  imem_addr,
  input  wire [31:0]      imem_rdata,

  // Outputs to IF/ID register
  output wire [XLEN-1:0]  if_pc,
  output wire [31:0]      if_instruction,
  output wire             if_is_compressed,
  output wire             if_valid
);
```

**Implementation Steps:**
1. Create empty stage module files with interfaces
2. Extract IF stage logic (PC, instruction fetch)
3. Extract ID stage logic (decode, register read)
4. Extract EX stage logic (ALU, branch, forwarding)
5. Extract MEM stage logic (memory access, MMU)
6. Extract WB stage logic (writeback muxing)
7. Extract CSR forwarding to separate module
8. Extract privilege forwarding to separate module
9. Update main core to instantiate new modules
10. Run full regression after each stage extraction

**Files to Create:**
- `rtl/core/rv_core_if_stage.v`
- `rtl/core/rv_core_id_stage.v`
- `rtl/core/rv_core_ex_stage.v`
- `rtl/core/rv_core_mem_stage.v`
- `rtl/core/rv_core_wb_stage.v`
- `rtl/core/rv_core_csr_forward.v`
- `rtl/core/rv_core_priv_forward.v`

**Files to Modify:**
- `rtl/core/rv32i_core_pipelined.v` (major restructure)
- Makefile (add new files to build)

**Estimated Effort:** 4-6 hours (incremental extraction)
**Lines Saved:** 0 (actually adds ~100 lines for module overhead)
**Risk:** Low-Medium (careful extraction, test after each stage)
**Testing:** Full regression after each extraction step

**Benefits:**
- Much easier to understand and navigate
- Easier to review changes (smaller files)
- Better suited for team collaboration
- Easier to add new pipeline stages (e.g., for OoO execution)
- Clearer separation of concerns
- Easier to optimize individual stages

**Trade-offs:**
- More files to manage
- Slightly more module instantiation overhead
- Need to carefully manage inter-stage signals

---

### Task 1.3: Extract Trap Controller Module

**Problem:**
- Trap handling logic scattered across main core
- `compute_trap_target()` function in main core (30 lines)
- Privilege mode transitions mixed with other logic
- MRET/SRET logic intermixed

**Current Location:**
- `rv32i_core_pipelined.v` lines 456-486: `compute_trap_target()` function
- `rv32i_core_pipelined.v` lines 588-715: Privilege mode state machine
- CSR file also handles some trap logic

**Solution:**
Create `rtl/core/trap_controller.v` module that handles:
- Trap target computation (mtvec/stvec + cause offset)
- Privilege mode transitions on trap entry
- MRET/SRET return logic
- Delegation decision logic

**Module Interface:**
```verilog
module trap_controller #(
  parameter XLEN = 32
) (
  input  wire             clk,
  input  wire             reset_n,

  // Current state
  input  wire [1:0]       current_priv,
  input  wire [XLEN-1:0]  mtvec,
  input  wire [XLEN-1:0]  stvec,
  input  wire [XLEN-1:0]  medeleg,

  // Trap inputs
  input  wire             trap_taken,
  input  wire [XLEN-1:0]  trap_cause,
  input  wire             is_interrupt,

  // xRET inputs
  input  wire             mret_taken,
  input  wire             sret_taken,
  input  wire [1:0]       mpp,  // Machine Previous Privilege
  input  wire             spp,  // Supervisor Previous Privilege

  // Outputs
  output wire [XLEN-1:0]  trap_target,      // Target PC for trap
  output wire [1:0]       trap_target_priv, // Target privilege for trap
  output wire [1:0]       next_priv         // Next privilege mode
);
```

**Implementation Steps:**
1. Create `rtl/core/trap_controller.v` with interface
2. Move `compute_trap_target()` function to new module
3. Move privilege mode state machine logic
4. Update main core to instantiate trap controller
5. Connect trap controller outputs to pipeline flush logic
6. Run privilege mode tests to verify

**Files to Create:**
- `rtl/core/trap_controller.v`

**Files to Modify:**
- `rtl/core/rv32i_core_pipelined.v` (remove trap logic, add instantiation)
- Makefile (add to build)

**Estimated Effort:** 2-3 hours
**Lines Saved:** 100-150 lines from main core
**Risk:** Low (well-defined functionality)
**Testing:** Privilege mode tests (`make test-quick`)

**Benefits:**
- Clear ownership of trap-related logic
- Easier to verify trap handling
- Simpler to add features like nested traps
- Better matches RISC-V privilege spec structure

---

## Priority 2: Medium Impact, Low Risk 🟡

### Task 2.1: Consolidate Pipeline Register Modules

**Problem:**
- 4 separate pipeline register modules with similar structure
- Each ~200-400 lines
- Repeated patterns for valid, flush, stall, data
- Adding new pipeline signals requires updating 4 files

**Current Modules:**
- `ifid_register.v` - IF/ID pipeline register
- `idex_register.v` - ID/EX pipeline register (370 lines)
- `exmem_register.v` - EX/MEM pipeline register
- `memwb_register.v` - MEM/WB pipeline register

**Common Pattern:**
```verilog
// All modules have:
- input flush (clear valid bit)
- input stall (hold current values)
- input valid_in, output valid_out
- input [N:0] data_in, output [N:0] data_out
- Always block: if flush, clear; else if stall, hold; else latch
```

**Solution Option A: Parameterized Generic Module**
Create `rtl/core/pipeline_register.v` with parameterized data width:

```verilog
module pipeline_register #(
  parameter DATA_WIDTH = 32
) (
  input  wire                   clk,
  input  wire                   reset_n,
  input  wire                   flush,
  input  wire                   stall,
  input  wire                   valid_in,
  input  wire [DATA_WIDTH-1:0]  data_in,
  output reg                    valid_out,
  output reg  [DATA_WIDTH-1:0]  data_out
);
```

**Solution Option B: Keep Separate (Recommended)**
- Pipeline registers have different signal bundles
- IDEX has many more signals than IFID
- Parameterizing would make connections ugly
- Current approach is clear and explicit

**Recommendation:** **DO NOT IMPLEMENT**
- Code duplication is minimal (~50 lines per module)
- Each pipeline stage has unique signal requirements
- Explicit modules are more readable than parameterized generic
- Trade-off favors clarity over DRY principle here

**Decision:** Mark as REJECTED - keep current structure

---

### Task 2.2: Create Common Types/Constants Include File

**Problem:**
- Opcodes (R, I, S, B, U, J) defined in decoder
- ALU operation codes defined in control unit
- Privilege modes (U, S, M) defined in multiple places
- Exception codes scattered across modules

**Solution:**
Create `rtl/config/rv_types.vh` with:
```verilog
`ifndef RV_TYPES_VH
`define RV_TYPES_VH

// Instruction opcodes (from RISC-V spec)
localparam OP_LOAD      = 7'b0000011;
localparam OP_LOAD_FP   = 7'b0000111;
localparam OP_MISC_MEM  = 7'b0001111;
localparam OP_OP_IMM    = 7'b0010011;
localparam OP_AUIPC     = 7'b0010111;
// ... etc

// Privilege modes
localparam PRIV_U_MODE  = 2'b00;  // User mode
localparam PRIV_S_MODE  = 2'b01;  // Supervisor mode
localparam PRIV_M_MODE  = 2'b11;  // Machine mode

// Exception causes (from RISC-V spec Table 3.6)
localparam EXC_INSTR_ADDR_MISALIGN   = 4'd0;
localparam EXC_INSTR_ACCESS_FAULT    = 4'd1;
localparam EXC_ILLEGAL_INSTR         = 4'd2;
// ... etc

// ALU operations
localparam ALU_ADD  = 4'b0000;
localparam ALU_SUB  = 4'b0001;
localparam ALU_SLL  = 4'b0010;
// ... etc

`endif // RV_TYPES_VH
```

**Implementation Steps:**
1. Create `rtl/config/rv_types.vh`
2. Extract opcode definitions from decoder
3. Extract ALU ops from control/ALU
4. Extract privilege modes
5. Extract exception codes
6. Add includes to relevant modules
7. Run regression tests

**Files to Create:**
- `rtl/config/rv_types.vh`

**Files to Modify:**
- `rtl/core/decoder.v`
- `rtl/core/control.v`
- `rtl/core/alu.v`
- `rtl/core/exception_unit.v`
- `rtl/core/rv32i_core_pipelined.v`

**Estimated Effort:** 2-3 hours
**Lines Saved:** 40-60 lines
**Risk:** Low
**Testing:** Quick regression

**Benefits:**
- Single source of truth for type definitions
- Easier to maintain consistency
- Better documentation of instruction encoding
- Matches RISC-V spec organization

**Notes:**
- Keep Verilog-2001 compatible (use .vh not SystemVerilog package)
- Ensure compatibility with Icarus Verilog

---

## Priority 3: Nice to Have, Medium Risk 🟠

### Task 3.1: Refactor Forwarding Units for Consistency

**Problem:**
- `forwarding_unit.v` (300 lines) - EX stage forwarding
- `hazard_detection_unit.v` (301 lines) - ID stage forwarding + load-use hazards
- Similar logic patterns but different implementations
- Both handle data dependencies but at different pipeline stages

**Current Approach:**
- **Forwarding Unit**: Detects WAR/WAW hazards for EX stage ALU inputs
  - Forwards from MEM stage (exmem_rd -> ALU operand)
  - Forwards from WB stage (memwb_rd -> ALU operand)
  - 2-bit select signals: 00=none, 01=WB, 10=MEM

- **Hazard Detection Unit**: Detects load-use hazards, generates ID forwarding
  - Forwards from EX stage (idex_rd -> ID operands)
  - Forwards from MEM stage (exmem_rd -> ID operands)
  - Forwards from WB stage (memwb_rd -> ID operands)
  - 3-bit select signals: 000=none, 001=WB, 010=MEM, 100=EX
  - Also generates stall/flush for load-use hazards

**Potential Refactoring:**
1. Extract common dependency checking logic to shared functions
2. Standardize forwarding select encoding
3. Merge into single "data_hazard_unit.v" with ID and EX forwarding

**Recommendation:** **DEFER**
- Forwarding is performance-critical path
- Current implementation is well-tested and working
- Risk of introducing subtle timing bugs
- Wait until adding features like OoO execution that require major changes

**Decision:** Mark as DEFERRED - revisit when adding major pipeline changes

---

### Task 3.2: Add SystemVerilog Assertions (SVA)

**Problem:**
- `ENABLE_ASSERTIONS` flag exists but minimal assertions in code
- Internal invariants not checked during simulation
- Bugs may go undetected until causing visible failures

**Solution:**
Add SVA assertions for:

**Pipeline Invariants:**
```systemverilog
// Valid bits propagate correctly
property valid_propagation;
  @(posedge clk) disable iff (!reset_n)
  (ifid_valid && !flush_ifid && !stall_ifid) |=> idex_valid;
endproperty

// Only one exception source active at a time
property exclusive_exceptions;
  @(posedge clk) disable iff (!reset_n)
  $onehot0({exception_illegal_instr, exception_ecall,
            exception_load_misalign, exception_store_misalign});
endproperty

// Privilege mode is valid
property valid_privilege_mode;
  @(posedge clk) disable iff (!reset_n)
  (current_priv inside {2'b00, 2'b01, 2'b11});
endproperty
```

**CSR Assertions:**
```systemverilog
// MPP field only contains valid values (U, S, M)
property mpp_valid;
  @(posedge clk) disable iff (!reset_n)
  (mpp inside {2'b00, 2'b01, 2'b11});
endproperty

// CSR writes don't happen during invalid cycles
property no_csr_write_when_invalid;
  @(posedge clk) disable iff (!reset_n)
  (csr_we |-> idex_valid);
endproperty
```

**Forwarding Assertions:**
```systemverilog
// Forward only when destination matches source
property forward_on_match;
  @(posedge clk) disable iff (!reset_n)
  (forward_a == 2'b10) |-> (exmem_rd == idex_rs1);
endproperty
```

**Implementation Strategy:**
1. Add assertions to existing modules (guarded by `ENABLE_ASSERTIONS`)
2. Create separate `assertions/` directory with bind statements
3. Enable during development, disable for synthesis

**Tooling:**
- Icarus Verilog has limited SVA support
- May need Verilator or commercial tools for full SVA
- Can use simpler `assert` statements for basic checks

**Files to Create:**
- `rtl/assertions/rv_core_assertions.sv` (if using bind)

**Files to Modify:**
- All core RTL files (add inline assertions)

**Estimated Effort:** 4-6 hours
**Risk:** Low (assertions don't affect synthesis)
**Testing:** Enable assertions, run full regression

**Benefits:**
- Catch bugs earlier in development
- Document design invariants
- Easier debugging when assertions fail
- Industry best practice

**Limitations:**
- Icarus Verilog has limited SVA support
- May need different simulator for full benefit
- Adds simulation overhead

**Recommendation:** Implement basic assertions first, expand as tooling allows

---

## Priority 4: Future Enhancements 🔵

### Task 4.1: Create Formal Verification Harness

**Description:**
- Add bounded model checking for critical paths
- Verify CSR state machine transitions
- Verify forwarding logic correctness
- Use SymbiYosys or similar open-source tools

**Effort:** 8-12 hours
**Status:** FUTURE - after major refactoring complete

---

### Task 4.2: Modularize FPU Subsystem

**Current State:**
- FPU modules already well-separated
- `fpu.v` is top-level FPU integration (566 lines)
- Sub-modules: converter, adder, multiplier, divider, FMA, etc.

**Observation:**
- Already well-organized, no immediate need
- Only refactor if adding Vector extension (requires major FPU changes)

**Decision:** Mark as NOT NEEDED - current structure is good

---

### Task 4.3: Add Pipeline Performance Counters

**Description:**
- Add CSRs for performance monitoring (mcycle, minstret, mhpmcounterN)
- Track pipeline stalls, flushes, cache misses
- Useful for performance optimization

**Effort:** 4-6 hours
**Status:** FUTURE - useful for optimization work

---

## Implementation Roadmap

### Phase 1: Quick Wins (Session 1)
**Time:** 2-3 hours
**Status:** 1/2 tasks complete (50%)
**Tasks:**
1. ✅ Task 1.1: Extract CSR constants to header file (1 hour) - **COMPLETE**
2. ❌ Task 1.3: Extract trap controller module (2 hours) - **DEFERRED** (see analysis below)

**Testing:** `make test-quick` after each task

**Deliverables:**
- ✅ `rtl/config/rv_csr_defines.vh` (154 lines, 63 constants)
- ❌ `rtl/core/trap_controller.v` - **DEFERRED**
- ✅ Updated 4 core files (csr_file.v, rv32i_core_pipelined.v, hazard_detection_unit.v, exception_unit.v)
- ✅ All tests passing (14/14 quick regression)

**Task 1.1 Results (2025-10-26):**
- Created comprehensive CSR defines header with RISC-V spec references
- Removed 70 lines of duplicate localparam definitions
- Zero regressions - all tests passing

**Task 1.3 Analysis (2025-10-26):**
- **Attempted**: Created trap_controller.v (263 lines) to extract trap handling logic
- **Problem**: Trap handling is deeply intertwined with CSR updates:
  - CSR file computes `trap_target_priv` based on delegation logic
  - CSR file updates mepc/sepc/mcause/scause on trap entry
  - Trap controller would need to either:
    1. Duplicate CSR logic (violates DRY principle)
    2. Have CSR file as submodule (increases complexity)
    3. Split CSR updates from trap computation (breaks atomicity)
- **Issue**: Created combinational timing loops during integration
- **Decision**: **DEFER** until after Phase 2 (main core split)
- **Recommendation**: Extract trap controller AFTER splitting core into stages
  - Rationale: Stage-based design will clarify trap/CSR boundaries
  - Trap controller can then interface cleanly with dedicated CSR stage
- **Tests**: Reverted changes, all tests passing (14/14)

---

### Phase 2: Major Restructure (Session 2-3)
**Time:** 6-8 hours
**Tasks:**
1. Task 1.2: Split main core into stage modules (6-8 hours)
   - Extract incrementally (IF, ID, EX, MEM, WB, forwarding)
   - Test after each extraction
   - Update documentation

**Testing:** Full regression after each stage extraction

**Deliverables:**
- 7 new stage/forwarding modules
- Restructured main core (600-800 lines)
- Updated architecture docs
- All tests passing

---

### Phase 3: Polish (Session 4)
**Time:** 2-3 hours
**Tasks:**
1. Task 2.2: Create common types/constants file (2 hours)
2. Documentation updates (1 hour)
   - Update ARCHITECTURE.md with new module hierarchy
   - Update README with new file structure

**Testing:** Quick regression

**Deliverables:**
- `rtl/config/rv_types.vh`
- Updated documentation
- All tests passing

---

### Phase 4: Future Work (TBD)
**Tasks:**
- Task 3.2: Add SystemVerilog assertions
- Task 4.1: Formal verification harness
- Task 4.3: Performance counters

---

## Testing Strategy

### For Each Refactoring Task:
1. **Before Changes:**
   - Run `make test-quick` (14 tests, ~7s) - establish baseline
   - Document passing test count

2. **During Changes:**
   - Make incremental changes
   - Compile after each change
   - Fix compilation errors immediately

3. **After Changes:**
   - Run `make test-quick` - verify no regressions
   - Run full compliance tests: `env XLEN=32 ./tools/run_official_tests.sh all`
   - Run privilege mode tests: `env XLEN=32 make test-quick`
   - Verify 81/81 compliance + 25/34 privilege tests still passing

4. **Before Commit:**
   - Clean build: `make clean && make`
   - Full regression
   - Update docs if needed

### Regression Test Checklist:
- [ ] Quick regression: `make test-quick` (14/14 passing)
- [ ] Official compliance: 81/81 tests passing
- [ ] Privilege tests: 25/34 passing (same as before)
- [ ] No new warnings in compilation
- [ ] Code compiles cleanly with Icarus Verilog

---

## Rejected/Deferred Tasks

### REJECTED: Task 2.1 - Consolidate Pipeline Registers
**Reason:** Each pipeline stage has unique signal bundles; parameterization reduces readability without significant benefit. Current explicit modules are clearer.

### DEFERRED: Task 3.1 - Refactor Forwarding Units
**Reason:** Performance-critical path; risk of subtle bugs; well-tested current implementation. Revisit only when making major pipeline changes (e.g., OoO execution).

### NOT NEEDED: Task 4.2 - Modularize FPU
**Reason:** FPU is already well-organized with clear module boundaries. No immediate benefit from further modularization.

---

## Success Metrics

### Code Quality Metrics:
- [ ] Main core file reduced from 2,468 to <800 lines
- [ ] Zero duplication of CSR constants
- [ ] Zero duplication of privilege mode encodings
- [ ] Clear module hierarchy matching pipeline stages
- [ ] All modules <600 lines (guideline, not hard limit)

### Testing Metrics:
- [ ] 100% compliance maintained (81/81 tests)
- [ ] No regression in privilege tests (25/34 still passing)
- [ ] No new compilation warnings
- [ ] Build time not significantly increased

### Documentation Metrics:
- [ ] ARCHITECTURE.md updated with new module hierarchy
- [ ] All new modules have header comments
- [ ] README.md updated with new file structure
- [ ] This refactoring plan marked complete

---

## Risk Mitigation

### Risk: Breaking working functionality
**Mitigation:**
- Incremental changes with testing after each step
- Keep old code commented out during transition
- Git commit after each successful task
- Can revert to last known-good state

### Risk: Introducing timing issues
**Mitigation:**
- Module extraction doesn't change logic, only organization
- No changes to critical paths (forwarding, exceptions)
- Test with same simulator (Icarus Verilog)

### Risk: Making code harder to understand
**Mitigation:**
- Clear module interfaces with comments
- Update architecture documentation
- Follow established naming conventions
- Get feedback before finalizing

### Risk: Incompatibility with tools
**Mitigation:**
- Stick to Verilog-2001 (no SystemVerilog features)
- Test with Icarus Verilog (primary toolchain)
- Avoid synthesizer-specific constructs

---

## Conclusion

This refactoring plan focuses on high-value, low-risk improvements that will:
1. Make the codebase easier to understand and maintain
2. Reduce code duplication (DRY principle)
3. Improve separation of concerns
4. Facilitate future enhancements

**Recommended Start:** Phase 1 (Task 1.1 + 1.3) in next session
**Total Estimated Effort:** 10-14 hours across 3-4 sessions
**Expected Outcome:** More maintainable codebase, no loss of functionality

---

**Document Version:** 1.0
**Last Updated:** 2025-10-26
**Next Review:** After Phase 2 completion
