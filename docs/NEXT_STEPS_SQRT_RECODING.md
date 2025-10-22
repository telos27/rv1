# Next Steps: FPU Bugs - SQRT Implementation

**Date**: 2025-10-22
**Status**: RV32UF 10/11 passing (90%)
**Failing Tests**: rv32uf-p-fdiv (fsqrt only)

---

## Summary

**✅ Bug #38 FIXED**: FP Multiplier operand latching bug
- rv32uf-p-recoding now PASSING
- Progress: 9/11 → 10/11 (81% → 90%)

**❌ Bug #37 REMAINING**: FP Square Root implementation broken
- rv32uf-p-fdiv fails at test #11 (fsqrt)

---

## ✅ Bug #38 Fixed: FP Multiplier Operand Latching

### What Was Wrong
The fp_multiplier module was reading operands from wire inputs in the UNPACK state (1 cycle after start), but the FPU pipeline had already changed those wire values due to forwarding.

Example:
```
Cycle N:   IDLE, start=1, operand_a=0x40400000 (3.0)
Cycle N+1: UNPACK reads operand_a, but it's now 0x00000000!
Result: is_zero_a=1, produced NaN instead of -Inf for 3.0 × -Inf
```

### Fix
- Added `operand_a_latched` and `operand_b_latched` registers
- Latch operands in IDLE state when start is asserted
- Use latched values in UNPACK state

### Results
- rv32uf-p-recoding: ✅ PASSING (was FAILING)
- RV32UF: 10/11 passing (90%, was 81%)
- See: `docs/BUG_38_FMUL_OPERAND_LATCHING.md`

---

## Priority 1: Fix FSQRT (Bug #37)

### Current Status
- Bugs #34-#36 fixed (mantissa extraction, timing, width)
- Algorithm rewritten but still broken - returns 0x00000000
- Need working sqrt implementation

### Test Case
```
Input:  sqrt(π) = sqrt(0x40490FDB)
Expected: 0x3FE2DFC5 ≈ 1.7724539
Current:  0x00000000 (zero)
```

### Recommended Solution

**Use proven algorithm from reference implementation**:

1. **Berkeley HardFloat** (preferred)
   - Well-tested, IEEE 754 compliant
   - Available on GitHub: ucb-bar/berkeley-hardfloat
   - Look at `DivSqrtRecFNToRaw.scala` or similar

2. **Alternative: Newton-Raphson**
   - `x_{n+1} = 0.5 * (x_n + N/x_n)`
   - Requires 3-4 iterations for single precision
   - Can use existing FMUL, FADD, FDIV (all working)

3. **Quick hack for testing**
   - Disable fsqrt tests temporarily
   - Focus on recoding issue
   - Come back to sqrt later

### Effort Estimate
- Reference implementation: 3-5 hours
- Newton-Raphson: 4-6 hours
- Debug current algorithm: 6-10 hours (risky)

---

## Recommended Workflow

### ✅ Session 1 Complete: Fixed Bug #38 (Recoding)
- Diagnosed: FP multiplier operand latching bug
- Fixed: Added operand registers to capture inputs
- Verified: rv32uf-p-recoding PASSING
- Committed: Bug #38 documentation

### Session 2: Fix SQRT (3-5 hours)
1. Research Berkeley HardFloat sqrt implementation
2. Adapt algorithm to our fp_sqrt module
3. Test with sqrt(4.0), sqrt(9.0), sqrt(π)
4. Verify fdiv test passes
5. Commit fix

### Success Criteria
- ✅ rv32uf-p-recoding PASSING (Bug #38 fixed)
- ⬜ rv32uf-p-fdiv PASSING (Bug #37 pending)
- 🎯 RV32UF: 11/11 tests passing (100%)
- 🎯 All FPU operations working correctly
- 🎯 Ready to move to RV32D (double precision)

---

## Files to Check

### For SQRT (Bug #37)
- `rtl/core/fp_sqrt.v` - Main sqrt module
- `rtl/core/fpu.v` - FPU integration
- Berkeley HardFloat reference (external)

### ✅ For Recoding (Bug #38 - FIXED)
- `rtl/core/fp_multiplier.v` - Operand latching (FIXED)
- See: `docs/BUG_38_FMUL_OPERAND_LATCHING.md`

---

## Quick Commands

```bash
# Run single test with debug
env DEBUG_FPU=1 XLEN=32 ./tools/run_hex_tests.sh rv32uf-p-recoding

# Run all FPU tests
env XLEN=32 ./tools/run_official_tests.sh f

# Check git status
git status
git log --oneline -5

# Commit changes
git add <files>
git commit -m "Bug #XX Fixed: <description>"
```

---

## Current Git Status

### ✅ Completed This Session
- Bug #38 Fixed: FP Multiplier operand latching
- rv32uf-p-recoding: PASSING ✅
- RV32UF: 10/11 passing (90%)

### 📝 Files Modified
- `rtl/core/fp_multiplier.v` (operand latching)
- `docs/BUG_38_FMUL_OPERAND_LATCHING.md` (new)
- `docs/NEXT_STEPS_SQRT_RECODING.md` (updated)

### 🔄 Ready to Commit
```bash
git add rtl/core/fp_multiplier.v docs/
git commit -m "Bug #38 Fixed: FP Multiplier Operand Latching - rv32uf-p-recoding PASSING"
git push
```

---

**🎯 Next Session**: Fix Bug #37 (fsqrt algorithm) to reach 100% RV32UF compliance!
