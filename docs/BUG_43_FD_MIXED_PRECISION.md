# Bug #43: F+D Mixed Precision Support Incomplete

**Status**: 🚧 ROOT CAUSE IDENTIFIED - Multi-session fix required
**Severity**: HIGH (blocks all RV32F tests)
**Discovered**: 2025-10-22
**Progress**: Analysis complete, 1/10 modules fixed

---

## Summary

The RV32D refactoring (Bugs #27 & #28) successfully widened the FP register file from XLEN to FLEN=64 bits to support double-precision operations on RV32. However, this broke ALL RV32F (single-precision) tests because the FP arithmetic modules assume `FLEN` directly maps to the precision being computed, rather than checking the `fmt` signal.

**Impact**:
- **Before RV32D refactoring** (commit 7dc1afd): RV32UF 11/11 (100%) ✅
- **After RV32D refactoring** (commit 747a716): RV32UF 1/11 (9%) ❌ - only ldst passes

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

### Critical (Must Fix)

1. **fp_sign.v** ✅ **FIXED**
   - **Issue**: Sign bit extracted from [FLEN-1] instead of [31] for single-precision
   - **Fix**: Added `fmt` input, use generate block for FLEN=64/32 cases
   - **Status**: Complete

2. **fp_compare.v** ❌ **TODO**
   - **Issue**: Compares using wrong exponent/mantissa bit positions
   - **Impact**: FEQ.S, FLT.S, FLE.S all broken
   - **Lines**: 24-33 (field extraction)

3. **fp_classify.v** ❌ **TODO**
   - **Issue**: Classifies using wrong bit positions
   - **Impact**: FCLASS.S returns incorrect class
   - **Lines**: 21-23 (field extraction)

4. **fp_minmax.v** ❌ **TODO**
   - **Issue**: Min/max comparison uses wrong fields
   - **Impact**: FMIN.S, FMAX.S incorrect results
   - **Need to check**: Likely extracts sign or does direct comparison

### Medium Priority (Arithmetic Units)

5. **fp_adder.v** ❌ **TODO**
   - **Issue**: Exponent/mantissa extraction for alignment
   - **Impact**: FADD.S, FSUB.S incorrect results
   - **Need to check**: Internal field extraction logic

6. **fp_multiplier.v** ❌ **TODO**
   - **Issue**: Similar field extraction issues
   - **Impact**: FMUL.S incorrect results

7. **fp_divider.v** ❌ **TODO**
   - **Issue**: Similar field extraction issues
   - **Impact**: FDIV.S incorrect results

8. **fp_sqrt.v** ❌ **TODO**
   - **Issue**: Similar field extraction issues
   - **Impact**: FSQRT.S incorrect results

9. **fp_fma.v** ❌ **TODO**
   - **Issue**: Uses adder/multiplier internals, may inherit issues
   - **Impact**: FMADD.S, FMSUB.S, FNMADD.S, FNMSUB.S incorrect

10. **fp_converter.v** ❌ **TODO**
    - **Issue**: INT↔FP conversion may have field extraction issues
    - **Impact**: FCVT.S.W, FCVT.W.S, etc. incorrect
    - **Priority**: High (affects many tests)

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
- [ ] fp_compare.v fixed
- [ ] fp_classify.v fixed
- [ ] fp_minmax.v fixed
- [ ] fp_adder.v fixed
- [ ] fp_multiplier.v fixed
- [ ] fp_divider.v fixed
- [ ] fp_sqrt.v fixed
- [ ] fp_fma.v fixed
- [ ] fp_converter.v fixed
- [ ] RV32UF 11/11 passing
- [ ] RV32UD 9/9 passing

---

**Next Session**: Start with fp_compare.v, fp_classify.v, fp_minmax.v (Phase 1)

**Estimated Total Time**: 12-18 hours across 7 sessions

🤖 Generated with [Claude Code](https://claude.com/claude-code)
