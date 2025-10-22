# Next Steps: FPU Bugs - SQRT Implementation

**Date**: 2025-10-22
**Status**: RV32UF 10/11 passing (90%)
**Failing Tests**: rv32uf-p-fdiv (fsqrt only)

---

## Summary

**✅ Bug #38 FIXED**: FP Multiplier operand latching bug
- rv32uf-p-recoding now PASSING
- Progress: 9/11 → 10/11 (81% → 90%)

**✅ Bug #39 FIXED**: FP Square Root counter initialization
- Perfect squares now work (sqrt(4)=2, sqrt(9)=3)
- Progress: 0% fsqrt → 50% fsqrt working

**❌ Bug #40 REMAINING**: FP Square Root precision for non-perfect squares
- rv32uf-p-fdiv still fails at test #11
- Non-perfect squares incorrect (sqrt(π)=1.5 instead of 1.7724539)
- Requires algorithm rewrite

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

## Priority 1: Fix FSQRT (Bugs #39, #40)

### ✅ Bug #39 Fixed - Counter Initialization
- **Was**: Counter initialized to 15, expected 26 → skipped initialization
- **Fix**: Corrected counter initialization in UNPACK and COMPUTE states
- **Result**: Algorithm now executes and works for perfect squares

### ⚠️ Bug #40 Open - Precision for Non-Perfect Squares
- **Status**: Algorithm only accepts first bit, rejects all others
- **Impact**: sqrt(π) = 1.5 instead of 1.7724539
- **Root Cause**: After first acceptance, `ac - (2*root+1)` always negative

### Test Cases
```
sqrt(4.0):  ✅ 0x40000000 (2.0) - Correct
sqrt(9.0):  ✅ 0x40400000 (3.0) - Correct
sqrt(π):    ❌ 0x3FC00000 (1.5) - Should be 0x3FE2DFC5 (1.7724539)
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
- ✅ FSQRT perfect squares working (Bug #39 fixed)
- ⬜ rv32uf-p-fdiv PASSING (Bug #40 pending)
- 🎯 RV32UF: 10/11 tests passing (90%, was 81%)
- 🎯 Target: 11/11 tests (100%) - need Bug #40 fix
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
