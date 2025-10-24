# Session 20: Bug #52 Fixed - FCVT Instructions - RV32D 77%

**Date**: 2025-10-23
**Status**: ✅ COMPLETED
**RV32D Progress**: 66% → 77% (7/9 tests passing)

---

## Executive Summary

**MAJOR SUCCESS!** Fixed Bug #52 which prevented FCVT.S.D and FCVT.D.S instructions from working correctly. The bug existed in TWO locations with identical root cause: using funct7[5] instead of funct7[6] to distinguish FP↔FP from FP↔INT conversions.

**Result**: rv32ud-p-fcvt now **PASSES** ✅, improving RV32D compliance from 66% to **77%**!

---

## Bug #52: FCVT.S.D/D.S Not Writing to FP Register File

### Symptoms
- FCVT.S.D and FCVT.D.S instructions executed but didn't write to FP registers
- rv32ud-p-fcvt failed at test #10 (round-trip conversion of -1.5)
- FP register f13 remained 0.0 instead of receiving -1.5

### Root Cause Analysis

**The bug existed in TWO locations:**

#### Part 1: Control Unit (rtl/core/control.v:434)
```verilog
// BEFORE (WRONG):
if (funct7[5]) begin  // Intended to check for FP↔INT
  // FP↔INT path
end else begin
  // FP↔FP path - sets fp_reg_write = 1
end

// AFTER (CORRECT):
if (funct7[6]) begin  // Correctly checks for FP↔INT
  // FP↔INT path
end else begin
  // FP↔FP path - sets fp_reg_write = 1
end
```

**Why funct7[5] was wrong:**
- FCVT.S.D = 0x20 = 0b0100000 → funct7[5]=1, funct7[6]=0
- FCVT.D.S = 0x21 = 0b0100001 → funct7[5]=1, funct7[6]=0
- FCVT.W.S = 0x60 = 0b1100000 → funct7[5]=1, funct7[6]=1
- FCVT.S.W = 0x68 = 0b1101000 → funct7[5]=1, funct7[6]=1

**Conclusion**: funct7[5]=1 for ALL conversions! Only funct7[6] distinguishes:
- funct7[6]=0 → FP↔FP conversions
- funct7[6]=1 → FP↔INT conversions

#### Part 2: FPU Module (rtl/core/fpu.v:368)
```verilog
// BEFORE (WRONG):
assign cvt_op = funct7[5] ?
                  // INT↔FP conversions
                  (funct7[3] ? {2'b01, rs2[1:0]} : {2'b00, rs2[1:0]}) :
                  // FP↔FP conversions
                  (funct7[0] ? 4'b1001 : 4'b1000);

// AFTER (CORRECT):
assign cvt_op = funct7[6] ?
                  // INT↔FP conversions
                  (funct7[3] ? {2'b01, rs2[1:0]} : {2'b00, rs2[1:0]}) :
                  // FP↔FP conversions
                  (funct7[0] ? 4'b1001 : 4'b1000);
```

**Impact**: Even after Part 1 fixed fp_reg_write, the wrong operation (INT↔FP instead of FP↔FP) was being sent to the converter, producing incorrect results.

---

## Investigation Process

### Step 1: Added Pipeline Debug Tracing
Added `DEBUG_FCVT_PIPELINE` to track FCVT through all pipeline stages:
```verilog
// rtl/core/rv32i_core_pipelined.v:1876-1895
always @(posedge clk) begin
  if (idex_fp_alu_en && idex_fp_alu_op == 5'b01010 && idex_valid) begin
    $display("[IDEX] FCVT: fp_reg_write=%b, fp_rd_addr=f%0d", ...);
  end
  // Similar for EXMEM and MEMWB stages
end
```

**Finding**: `fp_reg_write=0` already in IDEX stage!

### Step 2: Added Control Unit Debug
Added `DEBUG_FCVT_CONTROL` to see control decode:
```verilog
// rtl/core/control.v:545-552
if (opcode == 7'b1010011 && is_fp_op && (funct7[6:2] == 5'b01000)) begin
  $display("[CONTROL] FCVT decode: funct7=%b, funct7[5]=%b, fp_reg_write=%b", ...);
end
```

**Finding**:
```
[CONTROL] FCVT decode: funct7=0100000, funct7[5]=1, fp_reg_write=0
```
Control unit taking wrong branch due to funct7[5]=1!

### Step 3: Fixed Control Unit
Changed `if (funct7[5])` to `if (funct7[6])` in control.v:437

**Result**: fp_reg_write now set to 1, but test still failed!

### Step 4: Added FPU Execution Debug
Added `DEBUG_FPU_EXEC` to track FPU operations:
```verilog
// rtl/core/rv32i_core_pipelined.v:311-327
if (fpu_start && idex_fp_alu_op == 5'b01010) begin
  $display("[FPU] FCVT START: fp_operand_a=%h, int_operand=%h", ...);
end
```

### Step 5: Added Converter Debug
Added `DEBUG_FCVT_TRACE` to fp_converter.v:
```verilog
// rtl/core/fp_converter.v:741-769
$display("[FCVT_D_S] fp_operand=%h", fp_operand_latched);
$display("[FCVT_D_S] sign=%b, exp=%h, man=%h", sign_s, exp_s, man_s);
```

**Finding**: Converter never reached FCVT_D_S case - still being decoded as INT↔FP!

### Step 6: Found Second Bug Location
Discovered same funct7[5] bug in fpu.v:368 cvt_op decode logic.

### Step 7: Fixed FPU Module
Changed `funct7[5]` to `funct7[6]` in fpu.v:369

**Result**: Test PASSES! ✅

---

## Debug Infrastructure Added

### 1. DEBUG_FCVT_PIPELINE
**File**: rtl/core/rv32i_core_pipelined.v:1876-1895
**Purpose**: Trace FCVT instructions through pipeline stages
**Output**:
```
[IDEX] FCVT: fp_reg_write=1, fp_rd_addr=f13, valid=1, pc=80000288
[EXMEM] FCVT: fp_reg_write=1, fp_rd_addr=f13, valid=1, pc=80000288, fp_result=...
[MEMWB] FCVT: fp_reg_write=1, fp_rd_addr=f13, valid=1, fp_result=...
```

### 2. DEBUG_FPU_EXEC
**File**: rtl/core/rv32i_core_pipelined.v:311-327
**Purpose**: Monitor FPU execution for FCVT operations
**Output**:
```
[FPU] START: op=10, rs1=f10, rs2=1, rd=f13, pc=80000288
[FPU] FCVT START: fp_operand_a=bff8000000000000, int_operand=...
[FPU] DONE: result=41efffffffc00000, busy=0, pc=80000288
```

### 3. DEBUG_FCVT_CONTROL
**File**: rtl/core/control.v:545-552
**Purpose**: Show control unit FCVT decode decisions
**Output**:
```
[CONTROL] FCVT decode: funct7=0100000, funct7[5]=1, fp_reg_write=1
```

### 4. DEBUG_FCVT_TRACE
**File**: rtl/core/fp_converter.v:741-769
**Purpose**: Detailed FCVT_D_S conversion trace
**Output**:
```
[FCVT_D_S] fp_operand=ffffffffbfc00000
[FCVT_D_S] sign=1, exp=7f, man=400000
[FCVT_D_S] is_nan=0, is_inf=0, is_zero=0
[FCVT_D_S] adjusted_exp=3ff
[FCVT_D_S] result={1, 3ff, 400000, 29'b0}
```

---

## Verification

### Test #10 Trace (FCVT round-trip)
```
Input: -1.5 double = 0xBFF8000000000000

Instruction 1: FCVT.S.D f13, f10 (PC=0x80000288)
  FPU receives: fp_operand = 0xBFF8000000000000
  cvt_op = 4'b1000 (FCVT_S_D) ✓
  Result: 0xBFC00000 (NaN-boxed as 0xFFFFFFFFBFC00000) ✓

Instruction 2: FCVT.D.S f13, f13 (PC=0x8000028c)
  FPU receives: fp_operand = 0xFFFFFFFFBFC00000
  cvt_op = 4'b1001 (FCVT_D_S) ✓
  Extract: sign=1, exp=0x7F, man=0x400000
  Compute: adjusted_exp = 127 + 1023 - 127 = 0x3FF
  Result: {1, 0x3FF, 0x400000, 29'b0} = 0xBFF8000000000000 ✓

Test passes! ✅
```

---

## Test Results

### Before Fix (Session 19)
```
RV32D: 66% (6/9 tests)
  rv32ud-p-fcvt...     FAILED (gp=21, test #10)
```

### After Fix (Session 20)
```
RV32D: 77% (7/9 tests)
  rv32ud-p-fcvt...     PASSED ✅
```

### Current Status
**Passing (7/9)**:
- rv32ud-p-fadd ✅
- rv32ud-p-fclass ✅
- rv32ud-p-fcmp ✅
- rv32ud-p-fcvt ✅ **← NEW!**
- rv32ud-p-fcvt_w ✅
- rv32ud-p-fmin ✅
- rv32ud-p-ldst ✅

**Failing (2/9)**:
- rv32ud-p-fdiv (division issues)
- rv32ud-p-fmadd (FMA issues)

---

## Commits

### Commit 1: Bug #52 Part 1 - Control Unit Fix
**SHA**: 580e50b
**Files**: rtl/core/control.v, rtl/core/rv32i_core_pipelined.v
**Changes**:
- Fixed funct7[5] → funct7[6] in control.v:437
- Added DEBUG_FCVT_PIPELINE, DEBUG_FPU_EXEC, DEBUG_FCVT_CONTROL

### Commit 2: Bug #52 Part 2 - FPU Module Fix
**SHA**: dddbbf0
**Files**: rtl/core/fpu.v, rtl/core/fp_converter.v
**Changes**:
- Fixed funct7[5] → funct7[6] in fpu.v:369
- Added DEBUG_FCVT_TRACE to fp_converter.v

---

## Key Lessons

1. **Same bug can exist in multiple locations**: The funct7[5] mistake was duplicated in both control.v and fpu.v

2. **Bit numbering is critical**: funct7[5] vs funct7[6] - a one-bit difference that caused complete instruction failure

3. **Layered debugging is essential**:
   - Pipeline debug → identified write enable issue
   - Control debug → found first bug location
   - Converter debug → found second bug location

4. **RISC-V spec details matter**: Understanding exact bit patterns in instruction encoding (0x20 vs 0x60) was crucial

5. **Test early, test often**: After Part 1 fix, running full test revealed Part 2 was still broken

---

## Next Session Plan

**Goal**: Investigate remaining RV32D failures (23% gap)

**Targets**:
1. **rv32ud-p-fdiv** - Floating-point division
   - Likely precision issues in divider
   - May have special case handling bugs (NaN, infinity, zero)

2. **rv32ud-p-fmadd** - Fused multiply-add
   - Complex 3-operand instruction
   - Rounding/precision in multi-step operation

**Approach**:
- Run with DEBUG_FPU to see which test fails
- Analyze FPU divider and FMA units
- Check for precision loss, rounding errors, special case handling

---

## Performance Metrics

```
rv32ud-p-fcvt final run:
  Total cycles:        194
  Total instructions:  167
  CPI:                 1.162
  Stall cycles:        30 (15.5%)
  Flush cycles:        7 (3.6%)
  Status:              PASSED ✅
```

---

## Summary

Bug #52 was a critical issue that prevented all FCVT.S.D and FCVT.D.S instructions from working. The bug was caused by using the wrong bit (funct7[5] instead of funct7[6]) to distinguish between FP↔FP and FP↔INT conversions. This mistake existed in two locations and required two fixes.

Through systematic debugging with custom trace infrastructure, we identified both bug locations, fixed them, and achieved a **77% RV32D compliance rate** - an 11 percentage point improvement!

The remaining 23% gap (2 failing tests) is concentrated in algorithmically complex operations: division and fused multiply-add. These will be the focus of the next session.
