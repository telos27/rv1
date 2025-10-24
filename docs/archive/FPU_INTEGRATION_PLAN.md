# FPU Integration Plan for rv32i_core_pipelined.v

**Date**: 2025-10-10
**Status**: Planning Phase
**Scope**: Integrate FPU top-level module into 5-stage pipelined core

## Overview

The FPU (rtl/core/fpu.v) has been created and integrates all 10 FP arithmetic units. Now we need to wire it into the pipelined core. This is a significant modification affecting multiple pipeline stages.

## Current Status

- ✅ FPU top-level module created (rtl/core/fpu.v - 475 lines)
- ✅ All 9 FP arithmetic units functional (except converter which has syntax errors)
- ✅ FP register file created (rtl/core/fp_register_file.v)
- ✅ Decoder updated for FP instructions (rtl/core/decoder.v)
- ✅ Control unit updated for FP signals (rtl/core/control.v)
- ⏳ Pipeline integration: NOT STARTED

## Integration Checklist

### 1. Add FP Register File (ID Stage)
- [ ] Instantiate `fp_register_file` module
- [ ] Add 3 read ports: rs1, rs2, rs3 (for FMA instructions)
- [ ] Add 1 write port from WB stage
- [ ] Connect to decoder rs1/rs2/rs3 addresses
- [ ] Wire FP write-back data from WB stage

**Estimated Lines**: ~20 lines

### 2. Update Decoder Instantiation (ID Stage)
- [x] Decoder already outputs FP-related signals (from Phase 8.1):
  - `is_fp`, `is_fp_load`, `is_fp_store`, `is_fp_op`, `is_fp_fma`
  - `fp_fmt`, `fp_rm`, `rs3` (for R4-type)
- [ ] Wire decoder FP outputs to ID stage signals
- [ ] Pass FP signals to control unit

**Estimated Lines**: ~10 lines

### 3. Update Control Instantiation (ID Stage)
- [x] Control already generates FP control signals (from Phase 8.1):
  - `fp_reg_write`, `int_reg_write_fp`, `fp_mem_op`
  - `fp_alu_en`, `fp_alu_op`, `fp_use_dynamic_rm`
- [ ] Wire control FP outputs to ID stage control signals
- [ ] Pass FP control signals through pipeline registers

**Estimated Lines**: ~10 lines

### 4. Update ID/EX Pipeline Register
- [ ] Add FP operands: `fp_rs1_data`, `fp_rs2_data`, `fp_rs3_data`
- [ ] Add FP control signals: `fp_alu_en`, `fp_alu_op`, `fp_reg_write`
- [ ] Add rounding mode: `rounding_mode` (from `frm` CSR or instruction)
- [ ] Modify `rtl/core/idex_register.v` or add fields to instantiation

**Estimated Lines**: ~30 lines (pipeline register) + ~15 lines (instantiation)

### 5. Instantiate FPU (EX Stage)
- [ ] Add FPU module instantiation
- [ ] Connect FP operands from IDEX register
- [ ] Connect integer operand (for INT→FP conversions)
- [ ] Connect rounding mode
- [ ] Capture FPU outputs: `fp_result`, `int_result`, `busy`, `done`, `flags`

**Estimated Lines**: ~30 lines

### 6. Handle FPU Multi-Cycle Operations (EX Stage)
- [ ] When FPU is busy:
  - Stall pipeline (prevent new instructions from entering EX)
  - Hold IDEX register values
  - Assert stall signal to hazard detection unit
- [ ] When FPU asserts `done`:
  - Allow result to proceed to MEM stage
  - Release pipeline stall

**Estimated Lines**: ~20 lines

### 7. Update EX/MEM Pipeline Register
- [ ] Add FP result: `fp_result`
- [ ] Add integer result: `int_result` (for FP compare/classify/FMV.X.W)
- [ ] Add FP flags: `flag_nv`, `flag_dz`, `flag_of`, `flag_uf`, `flag_nx`
- [ ] Add FP control: `fp_reg_write`, `int_reg_write_fp`
- [ ] Modify `rtl/core/exmem_register.v` or add fields to instantiation

**Estimated Lines**: ~20 lines (pipeline register) + ~10 lines (instantiation)

### 8. Update MEM/WB Pipeline Register
- [ ] Add FP result: `fp_result`
- [ ] Add integer result from FP ops: `int_result_fp`
- [ ] Add FP control: `fp_reg_write`, `int_reg_write_fp`
- [ ] Modify `rtl/core/memwb_register.v` or add fields to instantiation

**Estimated Lines**: ~15 lines (pipeline register) + ~10 lines (instantiation)

### 9. Update Write-Back Stage (WB)
- [ ] Add FP register file write-back path
- [ ] Multiplex between FP result and integer result for FP ops
- [ ] Handle `int_reg_write_fp` (FP compare/classify/FMV.X.W write to integer regfile)
- [ ] Update integer register write-back mux for FP→INT results

**Estimated Lines**: ~25 lines

### 10. Update CSR File for FCSR Updates
- [ ] Wire FPU exception flags to CSR file
- [ ] Accumulate flags into `fflags` CSR (bitwise OR)
- [ ] Read `frm` CSR for dynamic rounding mode
- [ ] CSR file already has `fflags`, `frm`, `fcsr` from Phase 8.1

**Estimated Lines**: ~15 lines

### 11. Add FP Forwarding Paths
- [ ] FP forwarding is similar to integer forwarding:
  - EX→EX forwarding (EXMEM.fp_result → FPU operands)
  - MEM→EX forwarding (MEMWB.fp_result → FPU operands)
  - WB→ID forwarding (FP regfile bypass)
- [ ] Update `forwarding_unit.v` or add FP-specific forwarding logic

**Estimated Lines**: ~40 lines (forwarding unit) + ~20 lines (muxing)

### 12. Add FP Hazard Detection
- [ ] Detect FP load-use hazards (similar to integer)
- [ ] Detect FP multi-cycle operation stalls (FPU busy)
- [ ] Detect FP RAW hazards (read-after-write)
- [ ] Update `hazard_detection_unit.v` or add FP-specific logic

**Estimated Lines**: ~30 lines

### 13. FP Load/Store Memory Interface
- [ ] Add FP memory operations to data memory
- [ ] FLW/FLD: Load from memory → FP register file
- [ ] FSW/FSD: Store FP register → memory
- [ ] Handle NaN-boxing for single-precision loads

**Estimated Lines**: ~25 lines

## Total Estimated Integration Effort

- **New lines to add**: ~350-400 lines
- **Modules to modify**:
  1. `rv32i_core_pipelined.v` (main integration - ~250 lines)
  2. `idex_register.v` (~30 lines)
  3. `exmem_register.v` (~20 lines)
  4. `memwb_register.v` (~15 lines)
  5. `forwarding_unit.v` (~40 lines)
  6. `hazard_detection_unit.v` (~30 lines)

- **Estimated Time**: 6-8 hours for full integration + testing

## Phased Approach (Recommended)

### Phase A: Basic FPU Wiring (No Hazards)
1. Add FP register file
2. Instantiate FPU in EX stage
3. Add pipeline register fields
4. Basic write-back path
5. **Goal**: Simple FP ADD instruction works

### Phase B: Multi-Cycle and Stalls
1. Handle FPU busy signal
2. Pipeline stall logic
3. **Goal**: Multi-cycle ops (DIV, SQRT) work correctly

### Phase C: Forwarding and Hazards
1. FP forwarding paths
2. FP hazard detection
3. Load-use hazards
4. **Goal**: Back-to-back FP dependencies work

### Phase D: Load/Store and CSR
1. FP memory operations
2. FCSR flag accumulation
3. **Goal**: Full F/D extension functional

## Testing Strategy

1. **Unit Test**: Simple FP ADD (no hazards)
2. **Multi-Cycle Test**: FP DIV/SQRT
3. **Hazard Test**: Back-to-back FP dependencies
4. **FMA Test**: 4-operand FMA instruction
5. **Load/Store Test**: FLW/FSW memory operations
6. **FCSR Test**: Exception flag accumulation

## Known Issues and TODOs

1. **fp_converter.v has syntax errors**: Wire declarations inside case statements
   - Temporarily stubbed out in fpu.v
   - Need to refactor converter module

2. **FP Compare operation decoding**: FEQ/FLT/FLE not distinguished yet
   - Need to pass `funct3` to FPU or decode in control unit

3. **FP Converter operation decoding**: FCVT operation type not passed yet
   - Need to pass `funct5` or decode in control unit

4. **NaN-boxing**: Single-precision in double-precision registers
   - Need to implement in FP register file writes

5. **Rounding mode dynamic selection**:
   - Instruction can specify `rm=111` (dynamic)
   - Must read from `frm` CSR in this case

## Next Session Recommendations

**Option 1 (Recommended)**: Start with Phase A (Basic Wiring)
- Simpler, gets something working quickly
- Can test basic FP operations without complexity
- Build incrementally

**Option 2**: Full integration in one session
- More comprehensive but riskier
- Longer debugging cycle
- Good if confident in design

**I recommend Option 1** - Let's get basic FP ADD working first, then layer on complexity.

## File Modifications Summary

| File | Lines to Add | Complexity | Priority |
|------|--------------|------------|----------|
| rv32i_core_pipelined.v | ~250 | High | P0 |
| idex_register.v | ~30 | Medium | P0 |
| exmem_register.v | ~20 | Medium | P0 |
| memwb_register.v | ~15 | Low | P0 |
| forwarding_unit.v | ~40 | Medium | P1 |
| hazard_detection_unit.v | ~30 | Medium | P1 |
| fp_converter.v | Fix syntax | High | P2 |

## References

- RISC-V F/D Extension Spec: Chapter 11-12
- FPU Design Doc: `docs/FD_EXTENSION_DESIGN.md`
- FPU Module: `rtl/core/fpu.v`
- Control Signals: `rtl/core/control.v` (lines 98-117)
