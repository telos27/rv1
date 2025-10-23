# Bug #43: F+D Mixed Precision Support Incomplete

**Status**: 🚧 PHASE 2 IN PROGRESS - 7/10 modules fixed (fp_multiplier, fp_converter done)
**Severity**: HIGH (blocks 5 RV32F tests)
**Discovered**: 2025-10-22
**Progress**: Phase 1 complete (4/4 simple modules) + Phase 2 partial (3/6 complex modules fixed)

---

## Summary

The RV32D refactoring (Bugs #27 & #28) successfully widened the FP register file from XLEN to FLEN=64 bits to support double-precision operations on RV32. However, this broke ALL RV32F (single-precision) tests because the FP arithmetic modules assume `FLEN` directly maps to the precision being computed, rather than checking the `fmt` signal.

**Impact**:
- **Before RV32D refactoring** (commit 7dc1afd): RV32UF 11/11 (100%) ✅
- **After RV32D refactoring** (commit 747a716): RV32UF 1/11 (9%) ❌ - only ldst passes
- **After Phase 1 fixes** (2025-10-23): RV32UF 4/11 (36%) 🚧 - ldst, fclass, fcmp, fmin passing
- **After Phase 2 partial** (2025-10-22): RV32UF 6/11 (54%) 🚧 - +recoding, +fcvt now passing

---

## Root Cause

### Architecture Change

**OLD Design** (pre-RV32D):
- FLEN hardcoded to 32 for F-extension
- All FP modules operate on 32-bit values
- Sign bit at [31], exponent at [30:23], mantissa at [22:0]

**NEW Design** (post-RV32D):
- FLEN=64 to support both F and D extensions
- Single-precision values NaN-boxed in 64-bit registers: `{32'hFFFFFFFF, float32}`
- Double-precision values use full 64 bits

### The Problem

When FLEN=64, FP modules extract fields using **FLEN-relative positions**:
- Sign: `operand[FLEN-1]` = `operand[63]` ❌ (should be [31] for single-precision)
- Exponent: `operand[FLEN-2:MAN_WIDTH]` = `operand[62:52]` ❌ (should be [30:23] for SP)
- Mantissa: `operand[MAN_WIDTH-1:0]` = `operand[51:0]` ❌ (should be [22:0] for SP)

**What should happen**:
- Single-precision (fmt=0): Extract from bits [31:0], ignore NaN-boxing [63:32]
- Double-precision (fmt=1): Extract from bits [63:0]

---

## Test Results

### Current Failures
```
RV32UF (Single-Precision FP): 1/11 passing (9%)
✅ rv32uf-p-ldst      - PASSING (load/store doesn't extract bit fields)
❌ rv32uf-p-fadd      - FAILED (arithmetic uses wrong exponent/mantissa)
❌ rv32uf-p-fclass    - FAILED (classify extracts wrong bits)
❌ rv32uf-p-fcmp      - FAILED (compare extracts wrong sign/exponent)
❌ rv32uf-p-fcvt      - FAILED (conversion logic affected)
❌ rv32uf-p-fcvt_w    - FAILED (conversion logic affected)
❌ rv32uf-p-fdiv      - FAILED (divider uses wrong fields)
❌ rv32uf-p-fmadd     - FAILED (FMA uses wrong fields)
❌ rv32uf-p-fmin      - FAILED (min/max compares wrong bits)
❌ rv32uf-p-move      - FAILED (sign injection uses wrong bit)
❌ rv32uf-p-recoding  - FAILED (multiple operations affected)
```

### Symptom: Test Hangs
Some tests timeout with 99.8% pipeline flush rate, indicating undefined (X) values in critical paths causing comparison failures and infinite loops.

---

## Affected Modules

### Phase 1: Simple Modules (Combinational) ✅ COMPLETE

1. **fp_sign.v** ✅ **FIXED** (2025-10-22)
   - **Issue**: Sign bit extracted from [FLEN-1] instead of [31] for single-precision
   - **Fix**: Added `fmt` input, use generate block for FLEN=64/32 cases
   - **Impact**: FSGNJ.S, FSGNJN.S, FSGNJX.S now working

2. **fp_compare.v** ✅ **FIXED** (2025-10-23)
   - **Issue**: Compares using wrong exponent/mantissa bit positions
   - **Fix**: Format-aware field extraction with generate blocks
   - **Impact**: FEQ.S, FLT.S, FLE.S now working → **fcmp test PASSING** ✅

3. **fp_classify.v** ✅ **FIXED** (2025-10-23)
   - **Issue**: Classifies using wrong bit positions
   - **Fix**: Format-aware field extraction and special value detection
   - **Impact**: FCLASS.S now working → **fclass test PASSING** ✅

4. **fp_minmax.v** ✅ **FIXED** (2025-10-23)
   - **Issue**: Min/max comparison uses wrong fields
   - **Fix**: Format-aware field extraction and canonical NaN handling
   - **Impact**: FMIN.S, FMAX.S now working → **fmin test PASSING** ✅

### Phase 2: Complex Modules (Multi-cycle State Machines) 🚧 IN PROGRESS

5. **fp_adder.v** ✅ **FIXED** (2025-10-23)
   - **Issue**: ROUND stage extracted mantissa from wrong bit positions
   - **Root Cause**: After FLEN=64 refactoring, single-precision mantissas stored as:
     - `man_a[52:0] = {implicit_1[52], mantissa[51:29], padding[28:0]}`
     - After ALIGN: `aligned_man_a[55:0] = {implicit_1[55], mantissa[54:32], padding[31:3], GRS[2:0]}`
     - ROUND was extracting `normalized_man[25:3]` (from padding!) instead of `[54:32]` (actual mantissa)
   - **Fix**: Changed ROUND stage to extract `normalized_man[54:32]` for single-precision
   - **Also Fixed**: Zero-return cases in ALIGN stage to use correct bit ranges
   - **Status**: ✅ **WORKING** - fadd test progressed from test #5 → test #8 (now failing on FMUL)
   - **Impact**: FADD.S, FSUB.S now working correctly!

6. **fp_multiplier.v** ✅ **FIXED** (2025-10-22)
   - **Issue**: UNPACK/NORMALIZE/ROUND extracted fields from FLEN-relative positions
   - **Root Cause**: No fmt-based field extraction, used compile-time MAN_WIDTH/EXP_WIDTH
   - **Fix**:
     - Added `fmt` input and latched it
     - UNPACK: Conditional field extraction (single: [31:0], double: [63:0])
     - MULTIPLY: Correct bias selection (127 vs 1023)
     - NORMALIZE: Handle 29-bit padding in single-precision product
     - ROUND: NaN-boxing for single-precision results
     - Special cases: Proper NaN/Inf/Zero handling with NaN-boxing
   - **Status**: ✅ **WORKING** - recoding test now PASSING!
   - **Impact**: FMUL.S now working, recoding test fixed

7. **fp_divider.v** ❌ **TODO**
   - **Issue**: Similar field extraction issues
   - **Impact**: FDIV.S incorrect results → fdiv test failing
   - **Estimate**: 1-2 hours

8. **fp_sqrt.v** ❌ **TODO**
   - **Issue**: Similar field extraction issues
   - **Impact**: FSQRT.S incorrect results (tested in fdiv test)
   - **Estimate**: 1-2 hours

9. **fp_fma.v** ⚠️ **LOW PRIORITY**
   - **Issue**: May inherit issues from adder/multiplier
   - **Impact**: FMADD.S, FMSUB.S, FNMADD.S, FNMSUB.S incorrect
   - **Note**: Should work once adder and multiplier are fixed

10. **fp_converter.v** ✅ **FIXED** (2025-10-22)
    - **Issue**: FP→INT and INT→FP extracted fields from FLEN-relative positions
    - **Root Cause**: No fmt-based field extraction, used compile-time BIAS/MAN_WIDTH
    - **Fix**:
      - Added `fmt` input and latched it
      - FP→INT CONVERT: Conditional field extraction and correct bias (127 vs 1023)
      - INT→FP CONVERT: Correct bias and mantissa width based on format
      - ROUND: Proper result assembly with NaN-boxing for single-precision
    - **Status**: ✅ **WORKING** - fcvt test now PASSING!
    - **Impact**: FCVT.W.S, FCVT.S.W, and other conversions working

---

## Implementation Plan

### Phase 1: Simple Bit Extraction Modules (Session 1-2)
**Estimated**: 2-3 hours

1. ✅ fp_sign.v (DONE)
2. ❌ fp_compare.v - Add `fmt` input, extract fields conditionally
3. ❌ fp_classify.v - Add `fmt` input, extract fields conditionally
4. ❌ fp_minmax.v - Add `fmt` input, handle both precisions

**Pattern**:
```verilog
// OLD (FLEN=32 only):
wire sign = operand[FLEN-1];
wire [EXP_WIDTH-1:0] exp = operand[FLEN-2:MAN_WIDTH];

// NEW (F+D support):
input wire fmt;  // 0=single, 1=double

generate
  if (FLEN == 64) begin
    assign sign = fmt ? operand[63] : operand[31];
    assign exp = fmt ? operand[62:52] : operand[30:23];
    assign man = fmt ? operand[51:0] : operand[22:0];
  end else begin
    assign sign = operand[31];
    assign exp = operand[30:23];
    assign man = operand[22:0];
  end
endgenerate
```

### Phase 2: Arithmetic Modules (Session 3-5)
**Estimated**: 5-8 hours

5. ❌ fp_adder.v - Complex alignment logic
6. ❌ fp_multiplier.v - Mantissa multiplication
7. ❌ fp_divider.v - Division algorithm
8. ❌ fp_sqrt.v - Square root algorithm

**Challenges**:
- These modules have internal state machines
- Multiple stages of bit extraction/manipulation
- Need to verify rounding logic for both precisions

### Phase 3: Converter & FMA (Session 6)
**Estimated**: 3-4 hours

9. ❌ fp_fma.v - Fused multiply-add
10. ❌ fp_converter.v - INT↔FP conversions

### Phase 4: Testing & Verification (Session 7)
**Estimated**: 2-3 hours

- Run full RV32UF test suite (target: 11/11)
- Run full RV32UD test suite (target: 9/9)
- Mixed F/D operations test
- Update documentation

---

## Testing Strategy

### Incremental Testing
After each module fix:
```bash
# Test specific functionality
env XLEN=32 ./tools/run_official_tests.sh uf <test_name>

# Full single-precision suite
env XLEN=32 ./tools/run_official_tests.sh uf

# Full double-precision suite (when ready)
env XLEN=32 ./tools/run_official_tests.sh ud
```

### Success Criteria
- RV32UF: 11/11 (100%) ✅
- RV32UD: 9/9 (100%) ✅
- No test timeouts
- No undefined (X) values in simulation

---

## Technical Details

### NaN-Boxing Review
Per RISC-V spec, single-precision values in 64-bit FP registers must be NaN-boxed:
- Valid: `{32'hFFFFFFFF, float32_value}`
- Invalid: Any other upper 32 bits → treated as canonical NaN

### Field Positions

**Single-Precision (32-bit)**:
- Sign: bit [31]
- Exponent: bits [30:23] (8 bits)
- Mantissa: bits [22:0] (23 bits)

**Double-Precision (64-bit)**:
- Sign: bit [63]
- Exponent: bits [62:52] (11 bits)
- Mantissa: bits [51:0] (52 bits)

### Module Interface Pattern
All FP arithmetic modules need:
```verilog
module fp_xxx #(
  parameter FLEN = 32
) (
  input wire [FLEN-1:0] operand_a,
  input wire [FLEN-1:0] operand_b,
  input wire            fmt,        // ← ADD THIS
  // ... other ports
);
```

And FPU must pass `fmt` to all submodules:
```verilog
fp_xxx #(.FLEN(FLEN)) u_fp_xxx (
  .operand_a(operand_a),
  .operand_b(operand_b),
  .fmt(fmt),             // ← ADD THIS
  // ... other connections
);
```

---

## References

- RISC-V Unprivileged Spec v20191213: Section 11.2 (NaN-Boxing)
- rtl/core/fp_sign.v: Example of fixed module
- docs/SESSION_2025-10-22_RV32D_FLEN_REFACTORING.md: Original refactoring
- docs/BUG_28_FIX.md: Related memory interface changes

---

## Progress Tracking

- [x] Bug identified and root cause analyzed
- [x] fp_sign.v fixed
- [x] Documentation created
- [x] fp_compare.v fixed (Phase 1)
- [x] fp_classify.v fixed (Phase 1)
- [x] fp_minmax.v fixed (Phase 1)
- [x] fp_adder.v fixed (Phase 2) ✅ **NEW**
- [ ] fp_multiplier.v fixed (Phase 2) ← **NEXT**
- [ ] fp_divider.v fixed (Phase 2)
- [ ] fp_sqrt.v fixed (Phase 2)
- [ ] fp_fma.v fixed (Phase 3)
- [ ] fp_converter.v fixed (Phase 3)
- [ ] RV32UF 11/11 passing (currently 4/11 = 36%)
- [ ] RV32UD 9/9 passing

---

**Next Session**: Fix fp_multiplier.v (Phase 2) - apply same ROUND stage fix pattern

**Estimated Total Time**: 12-18 hours across 7 sessions

🤖 Generated with [Claude Code](https://claude.com/claude-code)
