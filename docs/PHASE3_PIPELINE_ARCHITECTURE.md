# Phase 3: Pipelined RV32I Processor Architecture

**Author**: RV1 Project
**Date**: 2025-10-10
**Status**: Planning
**Target**: 95%+ RISC-V Compliance

---

## Table of Contents
1. [Overview](#overview)
2. [Pipeline Stages](#pipeline-stages)
3. [Pipeline Registers](#pipeline-registers)
4. [Data Hazards and Forwarding](#data-hazards-and-forwarding)
5. [Control Hazards](#control-hazards)
6. [Load-Use Hazards](#load-use-hazards)
7. [Module Specifications](#module-specifications)
8. [Implementation Strategy](#implementation-strategy)
9. [Verification Plan](#verification-plan)

---

## Overview

### Design Goals
- **Eliminate RAW hazards** that cause 18 compliance test failures in Phase 1
- **Maintain CPI close to 1.0** with minimal stalls
- **Support all RV32I instructions** with proper hazard handling
- **Keep design FPGA-friendly** and synthesizable

### Pipeline Architecture
Classic **5-stage RISC pipeline**:

```
┌────────┬────────┬────────┬────────┬────────┐
│   IF   │   ID   │   EX   │  MEM   │   WB   │
│ Fetch  │ Decode │Execute │ Memory │ Write  │
│        │        │        │        │  Back  │
└────────┴────────┴────────┴────────┴────────┘
```

### Key Features
1. ✅ **Forwarding paths**: EX→EX, MEM→EX, WB→EX
2. ✅ **Hazard detection unit**: Detects load-use and control hazards
3. ✅ **Pipeline flushing**: For branches/jumps
4. ✅ **Stalling logic**: For unavoidable hazards
5. ✅ **Branch prediction**: Static predict-not-taken

---

## Pipeline Stages

### Stage 1: IF (Instruction Fetch)
**Function**: Fetch instruction from memory using PC

**Operations**:
- Read instruction memory at address `PC`
- Increment PC by 4 (for next instruction)
- Propagate `PC` and `instruction` to IF/ID register

**Timing**: 1 cycle (combinational read + register update)

**Outputs to IF/ID**:
- `pc` - Current program counter
- `instruction` - 32-bit instruction word
- `valid` - Instruction validity flag (for flushing)

---

### Stage 2: ID (Instruction Decode)
**Function**: Decode instruction, read registers, generate control signals

**Operations**:
- Decode instruction fields (opcode, rd, rs1, rs2, funct3, funct7)
- Extract and sign-extend immediates
- Read register file (rs1, rs2)
- Generate all control signals
- Detect hazards

**Hazard Detection**:
- Check if EX stage has a load instruction
- Check if EX.rd matches ID.rs1 or ID.rs2
- If hazard: stall IF and ID, insert bubble (NOP) into EX

**Outputs to ID/EX**:
- `pc` - Propagated from IF/ID
- `rs1_data`, `rs2_data` - Register values
- `rs1_addr`, `rs2_addr` - Source register addresses (for forwarding)
- `rd_addr` - Destination register address
- `imm` - Selected immediate value
- `control_signals` - All control signals (alu_control, mem_read, etc.)
- `valid` - Valid bit

---

### Stage 3: EX (Execute)
**Function**: Perform ALU operations, calculate branch targets

**Operations**:
- Select ALU operands (with forwarding muxes)
- Execute ALU operation
- Calculate branch/jump targets
- Evaluate branch conditions
- Propagate memory write data

**Forwarding Logic**:
```verilog
// Forward to operand A
if (MEM.reg_write && MEM.rd != 0 && MEM.rd == EX.rs1)
  operand_a = MEM.alu_result (or MEM.rd_data)
else if (WB.reg_write && WB.rd != 0 && WB.rd == EX.rs1)
  operand_a = WB.rd_data
else
  operand_a = EX.rs1_data

// Forward to operand B (similar logic)
```

**Branch Resolution**:
- Determine if branch is taken
- If taken or jump: flush IF and ID stages, update PC
- If not taken: continue normally

**Outputs to EX/MEM**:
- `alu_result` - ALU computation result
- `mem_write_data` - Data to write to memory (potentially forwarded rs2)
- `rd_addr` - Destination register
- `control_signals` - Propagated control signals
- `pc_plus_4` - For JAL/JALR write-back
- `valid` - Valid bit

---

### Stage 4: MEM (Memory Access)
**Function**: Access data memory for loads/stores

**Operations**:
- Read from data memory (if `mem_read`)
- Write to data memory (if `mem_write`)
- Propagate ALU result for non-memory instructions
- Select write-back data source

**Outputs to MEM/WB**:
- `alu_result` - Propagated from EX
- `mem_read_data` - Data read from memory
- `rd_addr` - Destination register
- `control_signals` - Write-back select signals
- `pc_plus_4` - For JAL/JALR
- `valid` - Valid bit

---

### Stage 5: WB (Write Back)
**Function**: Write result to register file

**Operations**:
- Select data to write back (ALU result, memory data, or PC+4)
- Write to register file (if `reg_write` is asserted)

**Write-Back Mux**:
```verilog
wb_data = (wb_sel == 2'b00) ? alu_result :
          (wb_sel == 2'b01) ? mem_read_data :
          (wb_sel == 2'b10) ? pc_plus_4 :
          32'h0;
```

**Note**: This stage updates the register file, making data available for forwarding to earlier stages.

---

## Pipeline Registers

### IF/ID Register
**Purpose**: Latch instruction fetch outputs

| Signal Name | Width | Description |
|-------------|-------|-------------|
| `pc` | 32 | Program counter for this instruction |
| `instruction` | 32 | Fetched instruction |
| `valid` | 1 | Valid instruction (0 = bubble/flush) |

**Control**:
- `stall`: Hold current values (for load-use hazard)
- `flush`: Replace with NOP bubble (for branch misprediction)

---

### ID/EX Register
**Purpose**: Latch decode stage outputs

| Signal Name | Width | Description |
|-------------|-------|-------------|
| `pc` | 32 | Program counter |
| `rs1_data` | 32 | Register source 1 data |
| `rs2_data` | 32 | Register source 2 data |
| `rs1_addr` | 5 | Register source 1 address (for forwarding) |
| `rs2_addr` | 5 | Register source 2 address (for forwarding) |
| `rd_addr` | 5 | Destination register address |
| `imm` | 32 | Immediate value |
| `opcode` | 7 | Opcode (for EX stage logic) |
| `funct3` | 3 | Funct3 field |
| **Control Signals** | | |
| `alu_control` | 4 | ALU operation select |
| `alu_src` | 1 | ALU operand B select |
| `branch` | 1 | Branch instruction |
| `jump` | 1 | Jump instruction |
| `mem_read` | 1 | Memory read enable |
| `mem_write` | 1 | Memory write enable |
| `reg_write` | 1 | Register write enable |
| `wb_sel` | 2 | Write-back data select |
| `valid` | 1 | Valid instruction |

**Control**:
- `flush`: Insert NOP (for branch or load-use hazard)

---

### EX/MEM Register
**Purpose**: Latch execute stage outputs

| Signal Name | Width | Description |
|-------------|-------|-------------|
| `alu_result` | 32 | ALU computation result |
| `mem_write_data` | 32 | Data to write to memory |
| `rd_addr` | 5 | Destination register address |
| `pc_plus_4` | 32 | PC+4 for JAL/JALR |
| `funct3` | 3 | For memory access size/sign |
| **Control Signals** | | |
| `mem_read` | 1 | Memory read enable |
| `mem_write` | 1 | Memory write enable |
| `reg_write` | 1 | Register write enable |
| `wb_sel` | 2 | Write-back data select |
| `valid` | 1 | Valid instruction |

---

### MEM/WB Register
**Purpose**: Latch memory stage outputs

| Signal Name | Width | Description |
|-------------|-------|-------------|
| `alu_result` | 32 | Propagated ALU result |
| `mem_read_data` | 32 | Data read from memory |
| `rd_addr` | 5 | Destination register address |
| `pc_plus_4` | 32 | PC+4 for JAL/JALR |
| **Control Signals** | | |
| `reg_write` | 1 | Register write enable |
| `wb_sel` | 2 | Write-back data select |
| `valid` | 1 | Valid instruction |

---

## Data Hazards and Forwarding

### RAW (Read-After-Write) Hazards

**Problem**: Instruction needs data from previous instruction that hasn't written back yet.

**Example**:
```assembly
add x1, x2, x3    # EX stage in cycle N
sub x4, x1, x5    # ID stage in cycle N (needs x1!)
```

### Forwarding Paths

#### 1. EX-to-EX Forwarding (1-cycle hazard)
**Scenario**: Result from EX stage forwarded to next instruction's EX stage
```assembly
add x1, x2, x3    # Cycle 3: EX stage produces x1
sub x4, x1, x5    # Cycle 4: EX stage needs x1 → Forward!
```

**Logic**:
```verilog
// Forward from EX/MEM to EX operand A
if (EXMEM_reg_write && EXMEM_rd != 0 && EXMEM_rd == IDEX_rs1)
  forward_a = 2'b10;  // Forward from EX/MEM.alu_result

// Forward from EX/MEM to EX operand B
if (EXMEM_reg_write && EXMEM_rd != 0 && EXMEM_rd == IDEX_rs2)
  forward_b = 2'b10;  // Forward from EX/MEM.alu_result
```

#### 2. MEM-to-EX Forwarding (2-cycle hazard)
**Scenario**: Result from MEM stage forwarded to EX stage
```assembly
add x1, x2, x3    # Cycle 4: MEM stage (alu_result available)
nop               # Cycle 5: (some instruction)
sub x4, x1, x5    # Cycle 5: EX stage needs x1 → Forward!
```

**Logic**:
```verilog
// Forward from MEM/WB to EX operand A (if not already forwarding from EX/MEM)
if (MEMWB_reg_write && MEMWB_rd != 0 && MEMWB_rd == IDEX_rs1
    && !(EXMEM_reg_write && EXMEM_rd != 0 && EXMEM_rd == IDEX_rs1))
  forward_a = 2'b01;  // Forward from MEM/WB.wb_data
```

**Priority**: EX/MEM forwarding takes priority over MEM/WB (most recent data)

#### 3. Forwarding Mux

```verilog
// Operand A selection
assign alu_operand_a = (forward_a == 2'b10) ? EXMEM_alu_result :
                       (forward_a == 2'b01) ? MEMWB_wb_data :
                       IDEX_rs1_data;

// Operand B selection (similar)
assign alu_operand_b_fwd = (forward_b == 2'b10) ? EXMEM_alu_result :
                           (forward_b == 2'b01) ? MEMWB_wb_data :
                           IDEX_rs2_data;

// Then apply alu_src mux
assign alu_operand_b = IDEX_alu_src ? IDEX_imm : alu_operand_b_fwd;
```

### Forwarding Unit

**Module**: `forwarding_unit.v`

**Inputs**:
- `IDEX_rs1`, `IDEX_rs2` - Source registers in EX stage
- `EXMEM_rd`, `EXMEM_reg_write` - Destination in MEM stage
- `MEMWB_rd`, `MEMWB_reg_write` - Destination in WB stage

**Outputs**:
- `forward_a[1:0]` - Forward select for operand A
  - `2'b00`: No forwarding (use IDEX.rs1_data)
  - `2'b01`: Forward from MEM/WB
  - `2'b10`: Forward from EX/MEM
- `forward_b[1:0]` - Forward select for operand B

---

## Control Hazards

### Branch/Jump Hazards

**Problem**: Don't know branch outcome until EX stage, but already fetching next instructions.

**Solution**: **Flush pipeline** on branch/jump

### Branch Resolution in EX Stage

**Strategy**:
1. Evaluate branch in EX stage (cycle 3)
2. By then, 2 instructions have been fetched (in IF and ID)
3. If branch taken or jump: flush those 2 instructions (insert bubbles)
4. Update PC to branch target

**Pipeline Flush on Taken Branch**:
```
Cycle 1: beq  (IF)
Cycle 2: beq  (ID),  instr1 (IF)
Cycle 3: beq  (EX),  instr1 (ID),  instr2 (IF)  ← Branch resolves!
         If taken: Flush instr1 and instr2
Cycle 4: beq  (MEM), NOP (EX), NOP (ID), target (IF)
```

**Implementation**:
```verilog
// In EX stage
wire branch_taken = branch && take_branch;
wire pc_change = branch_taken || jump;

// Flush control
assign flush_IFID = pc_change;
assign flush_IDEX = pc_change;
assign pc_src = pc_change ? branch_or_jump_target : pc_plus_4;
```

### Branch Prediction

**Phase 3 Initial**: Static **predict-not-taken**
- Always fetch PC+4
- If branch taken: pay 2-cycle penalty (flush 2 instructions)
- If branch not taken: no penalty

**Future Enhancement**: Dynamic branch prediction (BTB, 2-bit saturating counter)

---

## Load-Use Hazards

### The Problem

Load instruction produces data in MEM stage, but next instruction might need it in EX stage.

**Example**:
```assembly
lw  x1, 0(x2)     # Cycle 4: MEM stage produces x1
add x3, x1, x4    # Cycle 4: EX stage needs x1 → Too early!
```

**Cannot forward from MEM to EX in same cycle** (would need data before it's available).

### Solution: 1-Cycle Stall

**Strategy**: Detect load-use hazard in ID stage, stall pipeline for 1 cycle.

```
Original:
Cycle 1: lw  (IF)
Cycle 2: lw  (ID),    add (IF)
Cycle 3: lw  (EX),    add (ID)     ← Hazard detected!
Cycle 4: lw  (MEM),   add (EX)     ← add needs data, but lw still in MEM

With Stall:
Cycle 1: lw  (IF)
Cycle 2: lw  (ID),    add (IF)
Cycle 3: lw  (EX),    add (ID)     ← Hazard detected!
         Insert bubble into EX, stall ID and IF
Cycle 4: lw  (MEM),   NOP (EX),  add (ID)
Cycle 5: lw  (WB),    add (EX) with forwarding from MEM/WB
```

### Hazard Detection Unit

**Module**: `hazard_detection_unit.v`

**Logic**:
```verilog
wire load_use_hazard = IDEX_mem_read &&
                       ((IDEX_rd == IFID_rs1) || (IDEX_rd == IFID_rs2)) &&
                       (IDEX_rd != 5'h0);

assign stall_IF = load_use_hazard;
assign stall_ID = load_use_hazard;
assign flush_EX = load_use_hazard;  // Insert bubble (NOP) into EX
```

**Inputs**:
- `IDEX_mem_read` - Load instruction in EX stage
- `IDEX_rd` - Destination register of load
- `IFID_rs1`, `IFID_rs2` - Source registers of instruction in ID

**Outputs**:
- `stall_pc` - Hold PC
- `stall_IFID` - Hold IF/ID register
- `bubble_IDEX` - Insert NOP into ID/EX register

---

## Module Specifications

### Top-Level: `rv32i_core_pipelined.v`

**Parameters**:
- `RESET_VECTOR` - PC reset address (default: 0x00000000)
- `IMEM_SIZE` - Instruction memory size
- `DMEM_SIZE` - Data memory size

**Ports**:
```verilog
module rv32i_core_pipelined (
  input  wire        clk,
  input  wire        reset_n,

  // Debug outputs
  output wire [31:0] pc_out,
  output wire [31:0] instr_out,
  output wire        stall_out
);
```

---

### Pipeline Register Modules

#### 1. `ifid_register.v`
**Function**: IF/ID pipeline register with stall and flush

```verilog
module ifid_register (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        stall,      // Hold current value
  input  wire        flush,      // Clear to NOP

  // Inputs from IF stage
  input  wire [31:0] pc_in,
  input  wire [31:0] instruction_in,

  // Outputs to ID stage
  output reg  [31:0] pc_out,
  output reg  [31:0] instruction_out,
  output reg         valid_out
);
```

#### 2. `idex_register.v`
**Function**: ID/EX pipeline register with flush

```verilog
module idex_register (
  input  wire        clk,
  input  wire        reset_n,
  input  wire        flush,

  // Inputs from ID stage
  input  wire [31:0] pc_in,
  input  wire [31:0] rs1_data_in,
  input  wire [31:0] rs2_data_in,
  input  wire [4:0]  rs1_addr_in,
  input  wire [4:0]  rs2_addr_in,
  input  wire [4:0]  rd_addr_in,
  input  wire [31:0] imm_in,
  input  wire [6:0]  opcode_in,
  input  wire [2:0]  funct3_in,
  // ... all control signals ...

  // Outputs to EX stage
  output reg  [31:0] pc_out,
  output reg  [31:0] rs1_data_out,
  // ... etc ...
);
```

#### 3. `exmem_register.v`
**Function**: EX/MEM pipeline register

#### 4. `memwb_register.v`
**Function**: MEM/WB pipeline register

---

### Hazard Control Modules

#### 1. `forwarding_unit.v`
See [Data Hazards and Forwarding](#data-hazards-and-forwarding) section.

#### 2. `hazard_detection_unit.v`
See [Load-Use Hazards](#load-use-hazards) section.

---

### Reused Modules from Phase 1

These modules require **no changes**:
- ✅ `alu.v` - ALU operations
- ✅ `decoder.v` - Instruction decode
- ✅ `control.v` - Control signal generation
- ✅ `branch_unit.v` - Branch evaluation
- ✅ `data_memory.v` - Data memory
- ✅ `instruction_memory.v` - Instruction memory

These modules require **modifications**:
- ⚠️ `register_file.v` - No longer needs to worry about RAW hazards (forwarding handles it)
- ⚠️ `pc.v` - Needs stall input

---

## Implementation Strategy

### Step 1: Create Pipeline Registers (Week 1)
1. Implement `ifid_register.v` with stall/flush
2. Implement `idex_register.v` with flush
3. Implement `exmem_register.v`
4. Implement `memwb_register.v`
5. Write unit tests for each

**Verification**: Each register correctly latches, stalls, and flushes.

---

### Step 2: Build Basic Pipeline (Week 1-2)
1. Create `rv32i_core_pipelined.v` top-level
2. Instantiate all 5 stages with pipeline registers
3. Connect basic datapath (no forwarding yet)
4. Add NOP bubbles for ALL hazards temporarily

**Verification**: Simple non-dependent instruction sequences work.

---

### Step 3: Add Forwarding (Week 2)
1. Implement `forwarding_unit.v`
2. Add forwarding muxes in EX stage
3. Connect forwarding paths

**Verification**: Back-to-back dependent instructions work (AND, OR, XOR tests).

---

### Step 4: Add Hazard Detection (Week 2-3)
1. Implement `hazard_detection_unit.v`
2. Add stall logic for load-use hazards
3. Connect stall signals to PC and IF/ID

**Verification**: Load-use sequences work correctly.

---

### Step 5: Handle Control Hazards (Week 3)
1. Add branch resolution in EX stage
2. Implement pipeline flush logic
3. Connect PC update for branches/jumps

**Verification**: All branch and jump tests pass.

---

### Step 6: Integration and Compliance (Week 3-4)
1. Run full compliance test suite
2. Debug any remaining failures
3. Optimize critical paths
4. Performance analysis (CPI measurement)

**Target**: 95%+ compliance, CPI ≈ 1.1-1.3

---

## Verification Plan

### Unit Tests
- **Pipeline Registers**: Test stall, flush, normal operation
- **Forwarding Unit**: Test all forwarding cases
- **Hazard Detection**: Test load-use detection

### Integration Tests
**Test Categories**:
1. **No Hazards**: Independent instructions
2. **Data Hazards**:
   - EX-to-EX forwarding (1-cycle apart)
   - MEM-to-EX forwarding (2-cycles apart)
   - Load-use hazard (with stall)
3. **Control Hazards**:
   - Taken branches
   - Not-taken branches
   - JAL, JALR
4. **Mixed Hazards**: Multiple hazards in sequence

### Compliance Tests
- **Target**: 40+/42 tests passing
- **Known failures**: FENCE.I (not implemented), misaligned (out of scope)

### Performance Tests
- **Fibonacci**: Measure CPI
- **Bubble sort**: Measure CPI with load-use hazards
- **Compare to Phase 1**: Should be 2-4x faster despite same clock cycle count

---

## Expected Results

### Compliance Improvement
| Test Category | Phase 1 | Phase 3 (Target) |
|---------------|---------|------------------|
| Arithmetic    | ✅ PASS | ✅ PASS |
| Logical (R-type) | ❌ FAIL | ✅ PASS (forwarding) |
| Shifts        | ❌ FAIL | ✅ PASS (forwarding) |
| Load/Store    | ❌ FAIL | ✅ PASS (hazard detection) |
| Branches      | ✅ PASS | ✅ PASS |
| Jumps         | ✅ PASS | ✅ PASS |
| **Total**     | **24/42 (57%)** | **40+/42 (95%+)** |

### Performance Metrics
- **CPI (Cycles Per Instruction)**: ~1.1 - 1.3
  - 1.0 for no-hazard instructions
  - +0.1-0.3 for load-use stalls and branch mispredictions
- **Throughput**: Up to 5x single-cycle (5 instructions in pipeline)
- **Latency**: 5 cycles (per instruction completion)

---

## Implementation Checklist

### Phase 3.1: Pipeline Structure
- [ ] Create `ifid_register.v`
- [ ] Create `idex_register.v`
- [ ] Create `exmem_register.v`
- [ ] Create `memwb_register.v`
- [ ] Create `rv32i_core_pipelined.v` skeleton
- [ ] Unit test all pipeline registers

### Phase 3.2: Basic Datapath
- [ ] Connect IF stage
- [ ] Connect ID stage
- [ ] Connect EX stage (no forwarding)
- [ ] Connect MEM stage
- [ ] Connect WB stage
- [ ] Test with simple programs (no hazards)

### Phase 3.3: Forwarding
- [ ] Implement `forwarding_unit.v`
- [ ] Add forwarding muxes in EX
- [ ] Test EX-to-EX forwarding
- [ ] Test MEM-to-EX forwarding
- [ ] Run R-type compliance tests (AND, OR, XOR, shifts)

### Phase 3.4: Hazard Detection
- [ ] Implement `hazard_detection_unit.v`
- [ ] Add stall logic to PC
- [ ] Add stall logic to IF/ID
- [ ] Add bubble insertion to ID/EX
- [ ] Test load-use hazards
- [ ] Run load/store compliance tests

### Phase 3.5: Control Hazards
- [ ] Add branch resolution in EX
- [ ] Implement flush logic
- [ ] Test branch taken/not-taken
- [ ] Test JAL/JALR
- [ ] Run branch/jump compliance tests

### Phase 3.6: Verification
- [ ] Run all unit tests
- [ ] Run all integration tests
- [ ] Run full compliance suite (target 95%+)
- [ ] Performance analysis (CPI measurement)
- [ ] Documentation update

---

## Critical Design Decisions

### 1. Register File Write Timing
**Decision**: Keep synchronous write on positive edge
**Rationale**: Forwarding eliminates need for special register file timing

### 2. Branch Resolution Point
**Decision**: Resolve branches in EX stage (not earlier)
**Rationale**:
- Simple datapath (ALU already in EX)
- 2-cycle penalty acceptable for Phase 3
- Can optimize to ID stage in future if needed

### 3. Forwarding Source Priority
**Decision**: EX/MEM takes priority over MEM/WB
**Rationale**: EX/MEM has most recent data

### 4. Load-Use Hazard Handling
**Decision**: 1-cycle stall (no bypassing MEM to EX in same cycle)
**Rationale**: Simpler timing, synthesizable, minimal performance impact

### 5. Memory Interface
**Decision**: Keep synchronous memory (1-cycle read/write)
**Rationale**: FPGA-friendly, no multi-cycle memory stalls needed

---

## Next Steps

1. **Review this document** with team/instructor
2. **Create detailed module specifications** for new modules
3. **Set up testbench infrastructure** for pipeline testing
4. **Begin implementation** with pipeline registers
5. **Incremental testing** at each step

---

## References

- **Patterson & Hennessy**: "Computer Organization and Design" - Chapter 4 (Pipelining)
- **RISC-V ISA Specification**: Volume 1, Unprivileged Spec
- **Phase 1 Code**: `/home/lei/rv1/rtl/core/` - Reuse ALU, decoder, control, etc.
- **Compliance Results**: `/home/lei/rv1/docs/COMPLIANCE_DEBUGGING_SESSION.md`

---

**Document Status**: ✅ Complete - Ready for implementation
**Next Document**: Phase 3 Module Specifications (detailed Verilog interfaces)
