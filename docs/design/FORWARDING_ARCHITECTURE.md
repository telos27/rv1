# RV1 Forwarding Architecture

## Overview

The RV1 pipelined processor implements a centralized data forwarding architecture to resolve Read-After-Write (RAW) hazards in the pipeline. This document describes the forwarding mechanisms, design decisions, and implementation details.

**Key Design Principles:**
- **Centralized Control**: All forwarding logic is consolidated in `forwarding_unit.v`
- **Multi-Level Forwarding**: Supports EX→ID, MEM→ID, and WB→ID forwarding for early branch resolution
- **Priority-Based**: Most recent instruction data has highest priority (EX > MEM > WB)
- **Dual-Stage Support**: Separate forwarding paths for ID stage (branches) and EX stage (ALU operations)
- **Scalable**: Architecture designed to accommodate future superscalar extensions

## Pipeline Hazard Background

### RAW (Read-After-Write) Hazards

RAW hazards occur when an instruction needs a value that hasn't been written back yet:

```
Cycle:    1    2    3    4    5    6
ADDI x1, x0, 10    IF   ID   EX   MEM  WB
ADD  x2, x1, x1         IF   ID   EX   MEM  WB
                                 ^    ^
                                 |    |
                          Need x1 here (EX stage)
                          x1 written here (WB stage)
```

Without forwarding, this requires 3-cycle stalls. With forwarding, we can use the result as soon as it's computed.

### Load-Use Hazards

Special case where data isn't available until MEM stage:

```
Cycle:    1    2    3    4    5    6
LW   x1, 0(x2)         IF   ID   EX   MEM  WB
ADD  x3, x1, x4             IF   ID   [STALL] EX   MEM  WB
                                      ^      ^
                                      |      |
                               Need x1 here  Available here
```

This requires 1-cycle stall even with forwarding.

## Forwarding Architecture

### Two-Stage Forwarding System

Our architecture implements forwarding at **two pipeline stages**:

1. **ID Stage Forwarding** - For early branch resolution
2. **EX Stage Forwarding** - For ALU operations

```
Pipeline Stages:
  IF → ID → EX → MEM → WB
       ↑    ↑
       |    |
    ID Fwd  EX Fwd
```

#### Why ID-Stage Forwarding?

Branch instructions need operands in the ID stage to determine:
- Branch target address (computed in ID)
- Branch condition (evaluated in ID)

Early branch resolution reduces control hazard penalties from 3 cycles to 1 cycle.

#### Why EX-Stage Forwarding?

ALU operations read operands in the ID stage but don't use them until EX stage. Forwarding to EX stage allows:
- More time for data to propagate through pipeline
- Simpler hazard detection (only need to check for load-use hazards)

### Forwarding Unit Interface

The `forwarding_unit.v` module has the following interface:

```verilog
module forwarding_unit (
    // ========== ID Stage Forwarding (for branches) ==========
    // Integer register forwarding
    input  wire [4:0] id_rs1,              // Source register 1 in ID stage
    input  wire [4:0] id_rs2,              // Source register 2 in ID stage
    output reg  [2:0] id_forward_a,        // Forward control for rs1 (3-bit)
    output reg  [2:0] id_forward_b,        // Forward control for rs2 (3-bit)

    // FP register forwarding (for FP branches/compares)
    input  wire [4:0] id_fp_rs1,
    input  wire [4:0] id_fp_rs2,
    input  wire [4:0] id_fp_rs3,
    output reg  [2:0] id_fp_forward_a,
    output reg  [2:0] id_fp_forward_b,
    output reg  [2:0] id_fp_forward_c,

    // ========== EX Stage Forwarding (for ALU ops) ==========
    // Integer register forwarding
    input  wire [4:0] idex_rs1,            // Source register 1 in EX stage
    input  wire [4:0] idex_rs2,            // Source register 2 in EX stage
    output reg  [1:0] forward_a,           // Forward control for rs1 (2-bit)
    output reg  [1:0] forward_b,           // Forward control for rs2 (2-bit)

    // FP register forwarding
    input  wire [4:0] idex_fp_rs1,
    input  wire [4:0] idex_fp_rs2,
    input  wire [4:0] idex_fp_rs3,
    output reg  [1:0] fp_forward_a,
    output reg  [1:0] fp_forward_b,
    output reg  [1:0] fp_forward_c,

    // ========== Pipeline Stage Write Ports ==========
    // ID/EX register
    input  wire [4:0] idex_rd,
    input  wire       idex_reg_write,
    input  wire [4:0] idex_fp_rd,
    input  wire       idex_fp_reg_write,

    // EX/MEM register
    input  wire [4:0] exmem_rd,
    input  wire       exmem_reg_write,
    input  wire [4:0] exmem_fp_rd,
    input  wire       exmem_fp_reg_write,

    // MEM/WB register
    input  wire [4:0] memwb_rd,
    input  wire       memwb_reg_write,
    input  wire       memwb_int_reg_write_fp,  // FP→INT write (e.g., FMV.X.W)
    input  wire [4:0] memwb_fp_rd,
    input  wire       memwb_fp_reg_write,
    input  wire       memwb_fp_reg_write_int   // INT→FP write (e.g., FMV.W.X)
);
```

### Signal Encoding

#### ID Stage Forwarding (3-bit encoding)

ID stage can forward from three pipeline stages:

```verilog
id_forward_a/b encoding:
  3'b100 = Forward from EX stage (IDEX register)
  3'b010 = Forward from MEM stage (EXMEM register)
  3'b001 = Forward from WB stage (MEMWB register)
  3'b000 = No forwarding (use register file)
```

**Priority Order**: EX > MEM > WB (most recent first)

Example forwarding mux in `rv32i_core_pipelined.v`:

```verilog
assign id_rs1_data = (id_forward_a == 3'b100) ? ex_alu_result :      // Forward from EX
                     (id_forward_a == 3'b010) ? exmem_alu_result :   // Forward from MEM
                     (id_forward_a == 3'b001) ? wb_data :            // Forward from WB
                     id_rs1_data_raw;                                 // Use register file
```

#### EX Stage Forwarding (2-bit encoding)

EX stage can forward from two pipeline stages (MEM and WB):

```verilog
forward_a/b encoding:
  2'b10 = Forward from MEM stage (EXMEM register)
  2'b01 = Forward from WB stage (MEMWB register)
  2'b00 = No forwarding (use ID/EX register value)
```

**Priority Order**: MEM > WB (most recent first)

**Note**: EX cannot forward from EX (would be circular). If EX-stage data is needed in EX, that's a load-use hazard requiring a stall.

Example forwarding mux in `rv32i_core_pipelined.v`:

```verilog
assign ex_operand_a = (forward_a == 2'b10) ? exmem_alu_result :
                      (forward_a == 2'b01) ? wb_data :
                      idex_rs1_data;
```

### Forwarding Logic Implementation

#### ID Stage Integer Forwarding

```verilog
// ID Stage rs1 forwarding
always @(*) begin
    id_forward_a = 3'b000;  // Default: no forwarding

    // Priority 1: Forward from EX stage (most recent)
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs1))
        id_forward_a = 3'b100;

    // Priority 2: Forward from MEM stage
    else if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == id_rs1))
        id_forward_a = 3'b010;

    // Priority 3: Forward from WB stage
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == id_rs1))
        id_forward_a = 3'b001;
end

// ID Stage rs2 forwarding (identical logic for rs2)
always @(*) begin
    id_forward_b = 3'b000;
    if (idex_reg_write && (idex_rd != 5'h0) && (idex_rd == id_rs2))
        id_forward_b = 3'b100;
    else if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == id_rs2))
        id_forward_b = 3'b010;
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == id_rs2))
        id_forward_b = 3'b001;
end
```

**Key Design Points:**
1. **x0 Protection**: Never forward to x0 (`idex_rd != 5'h0`)
2. **Priority Encoding**: Most recent stage checked first
3. **Write Enable**: Only forward if instruction actually writes (`idex_reg_write`)
4. **Cross-File Forwarding**: `memwb_int_reg_write_fp` handles FP→INT moves (FMV.X.W)

#### EX Stage Integer Forwarding

```verilog
// EX Stage rs1 forwarding
always @(*) begin
    forward_a = 2'b00;  // Default: no forwarding

    // Priority 1: Forward from MEM stage (most recent available)
    if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == idex_rs1))
        forward_a = 2'b10;

    // Priority 2: Forward from WB stage
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == idex_rs1))
        forward_a = 2'b01;
end

// EX Stage rs2 forwarding (identical logic for rs2)
always @(*) begin
    forward_b = 2'b00;
    if (exmem_reg_write && (exmem_rd != 5'h0) && (exmem_rd == idex_rs2))
        forward_b = 2'b10;
    else if ((memwb_reg_write | memwb_int_reg_write_fp) &&
             (memwb_rd != 5'h0) && (memwb_rd == idex_rs2))
        forward_b = 2'b01;
end
```

### Floating-Point Forwarding

FP forwarding follows the same principles but with additional complexity:

1. **Three Operands**: FP fused multiply-add (FMA) uses rs1, rs2, rs3
2. **Cross-File Forwarding**:
   - INT→FP: `memwb_fp_reg_write_int` (FMV.W.X, FCVT.S.W)
   - FP→INT: `memwb_int_reg_write_fp` (FMV.X.W, FCVT.W.S)

Example ID-stage FP forwarding:

```verilog
// ID Stage fp_rs1 forwarding
always @(*) begin
    id_fp_forward_a = 3'b000;
    if (idex_fp_reg_write && (idex_fp_rd != 5'h0) && (idex_fp_rd == id_fp_rs1))
        id_fp_forward_a = 3'b100;
    else if (exmem_fp_reg_write && (exmem_fp_rd != 5'h0) && (exmem_fp_rd == id_fp_rs1))
        id_fp_forward_a = 3'b010;
    else if ((memwb_fp_reg_write | memwb_fp_reg_write_int) &&
             (memwb_fp_rd != 5'h0) && (memwb_fp_rd == id_fp_rs1))
        id_fp_forward_a = 3'b001;
end

// Similar logic for fp_rs2 and fp_rs3
```

## Critical Timing Paths

### ID Stage Forwarding Critical Path

```
Register File Read → Forwarding Comparison → Mux Selection → Branch Unit
```

This path is timing-critical because:
1. Register file has setup/hold requirements
2. Forwarding comparisons are 5-bit wide (register address)
3. 4:1 mux for forwarding selection
4. Branch comparison is combinational

**Optimization**: Forwarding comparisons are done in parallel with register file read.

### EX Stage Forwarding Critical Path

```
ALU Result → Forwarding Mux → ALU Input
```

Less critical than ID stage because:
1. No register file in the path
2. Simpler 3:1 mux
3. More pipeline stages to propagate

## Interaction with Hazard Detection

The forwarding unit works in conjunction with the `hazard_detection_unit.v`:

### Load-Use Hazards

Forwarding **cannot** resolve load-use hazards when load data is needed in EX stage:

```verilog
// In hazard_detection_unit.v
assign load_use_hazard = idex_mem_read &&
                         ((idex_rd == id_rs1) || (idex_rd == id_rs2)) &&
                         (idex_rd != 5'h0);
```

When detected:
1. Stall PC (don't fetch new instruction)
2. Stall IF/ID (keep current instruction in ID)
3. Insert bubble in ID/EX (NOP in EX stage)

### MMU Busy Stalls

Added in Phase 12 to prevent pipeline advancement during page table walks:

```verilog
// In hazard_detection_unit.v
wire mmu_stall;
assign mmu_stall = mmu_busy;

assign stall_pc   = load_use_hazard || fp_load_use_hazard || m_extension_stall ||
                    a_extension_stall || fp_extension_stall || mmu_stall;
assign stall_ifid = load_use_hazard || fp_load_use_hazard || m_extension_stall ||
                    a_extension_stall || fp_extension_stall || mmu_stall;
```

**Critical**: Without MMU stall, IF/ID stages advance while EX/MEM are held, causing instruction loss.

## Verification and Testing

### Test Coverage

Forwarding logic is verified through:

1. **Unit Tests**: Individual forwarding scenarios
2. **Integration Tests**: Full pipeline with hazards
3. **RISC-V Compliance Tests**: Official test suite (41/42 passing)

### Example Test Cases

#### EX→ID Forwarding (Branch)
```assembly
    ADDI x1, x0, 10    # Write x1 in cycle N
    BEQ  x1, x0, label # Read x1 in cycle N+1 (ID stage)
```
Without EX→ID forwarding: Branch uses stale x1 value
With EX→ID forwarding: Branch uses fresh x1 from EX stage

#### MEM→ID Forwarding (Branch after ALU)
```assembly
    ADD  x1, x2, x3    # Write x1 in cycle N
    NOP                # Cycle N+1
    BEQ  x1, x0, label # Read x1 in cycle N+2 (ID stage)
```
ADD is in MEM stage when BEQ is in ID stage.

#### Load-Use with Stall
```assembly
    LW   x1, 0(x2)     # Load in cycle N
    ADD  x3, x1, x4    # Use in cycle N+1 (requires stall)
```
Pipeline stalls 1 cycle, then forwards from MEM→EX.

### Debug Techniques

Enable pipeline tracing in `tb_core_pipelined.v`:

```verilog
if (cycle_count >= 85 && cycle_count <= 92) begin
    $display("[%0d] IF: PC=%h | ID: PC=%h | EX: PC=%h rd=x%0d | MEM: PC=%h | WB: rd=x%0d wen=%b",
             cycle_count, pc, DUT.ifid_pc, DUT.idex_pc, DUT.idex_rd_addr,
             DUT.exmem_pc, DUT.memwb_rd_addr, DUT.memwb_reg_write);
    $display("       Forwarding: id_fwd_a=%b id_fwd_b=%b ex_fwd_a=%b ex_fwd_b=%b",
             DUT.id_forward_a, DUT.id_forward_b, DUT.forward_a, DUT.forward_b);
    $display("       Hazards: stall=%b flush=%b | Data: rs1=%h rs2=%h",
             DUT.stall_pc, DUT.flush_idex, DUT.id_rs1_data, DUT.id_rs2_data);
end
```

## Performance Impact

### CPI Analysis

Without forwarding:
- ALU-to-ALU dependency: 3-cycle penalty
- Load-to-use: 3-cycle penalty
- Branch resolution: 3-cycle penalty

With ID+EX forwarding:
- ALU-to-ALU dependency: **0-cycle penalty** (forwarded)
- Load-to-use: **1-cycle penalty** (unavoidable)
- Branch resolution: **1-cycle penalty** (flush only)

**CPI Improvement**: ~30-40% for typical code

### Area Cost

Forwarding unit area:
- Comparators: 12x 5-bit comparators (60 bits total)
- Muxes: 6x 4:1 32-bit muxes (integer) + 6x 4:1 32-bit muxes (FP)
- Control logic: Minimal (combinational)

**Estimated**: <5% of total core area

## Future Extensions

### Superscalar (2-way) Considerations

Current architecture scales to 2-way superscalar with these modifications:

1. **Duplicate Forwarding Paths**: 2 instructions × 2 operands = 4 paths per stage
2. **Parameterize Forwarding Unit**:
   ```verilog
   parameter NUM_ISSUE = 2;  // Number of instructions issued per cycle

   input  wire [4:0] id_rs1 [NUM_ISSUE-1:0];
   output reg  [2:0] id_forward_a [NUM_ISSUE-1:0];
   ```

3. **Cross-Issue Forwarding**: Instruction 1 can forward to Instruction 0 in same cycle
4. **Write Port Arbitration**: Handle multiple writes to same register

**Refactoring Required**: Minimal - centralized design makes parameterization straightforward.

### Out-of-Order (OoO) Considerations

OoO execution requires different approach:
- **Register Renaming**: Eliminates WAW/WAR hazards
- **Bypass Network**: More complex than simple forwarding
- **Reorder Buffer**: Forwarding from ROB entries

Current forwarding unit would be **replaced** rather than extended for OoO.

## Design Rationale

### Why Centralize Forwarding?

**Before Phase 12** (Distributed):
- Inline comparisons scattered across `rv32i_core_pipelined.v`
- ~24 lines of duplicated logic
- Difficult to verify correctness
- Hard to extend for new features

**After Phase 12** (Centralized):
- Single `forwarding_unit.v` module (268 lines)
- Clear separation of concerns
- Easy to verify and debug
- Simple to parameterize for superscalar

### Why Two Encoding Schemes?

**ID Stage (3-bit)**:
- Needs EX→ID forwarding for early branch resolution
- Three possible sources: EX, MEM, WB
- Requires 3-bit encoding (4 states: 3 sources + no forward)

**EX Stage (2-bit)**:
- Cannot forward EX→EX (circular dependency)
- Two possible sources: MEM, WB
- 2-bit encoding sufficient (3 states: 2 sources + no forward)

This approach minimizes mux size while supporting all necessary forwarding paths.

## References

- **RISC-V Spec**: Volume 1, Appendix A (Pipeline Hazards)
- **Patterson & Hennessy**: Computer Organization and Design, Chapter 4.7
- **Phase 12 Analysis**: `docs/PHASE12_LOAD_USE_BUG_ANALYSIS.md`
- **Implementation**:
  - `rtl/core/forwarding_unit.v`
  - `rtl/core/rv32i_core_pipelined.v` (lines 200-250, 500-550)
  - `rtl/core/hazard_detection_unit.v`

## Summary

The RV1 forwarding architecture provides:

✓ **Complete RAW hazard resolution** (except load-use)
✓ **Multi-level forwarding** (EX→ID, MEM→ID, WB→ID)
✓ **Dual-stage support** (ID and EX stage forwarding)
✓ **Centralized design** (single source of truth)
✓ **Scalable** (ready for superscalar extension)
✓ **Verified** (41/42 RISC-V compliance tests passing)

**Key Insight**: Forwarding is the critical enabler for high-performance pipelined processors. Our centralized architecture provides maximum performance while maintaining simplicity and extensibility.
