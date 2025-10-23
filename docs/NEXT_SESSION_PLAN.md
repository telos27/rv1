# Next Session Plan: RV32D Bug Fixes Continue

**Current Status**: RV32D at 66% (6/9 tests passing)  
**Priority**: Fix rv32ud-p-fcvt test #5 failure (REGRESSION from decoding fix)

---

## Top Priority: rv32ud-p-fcvt Test #5 (REGRESSION)

### Background
- **Was passing before Session 18**
- Now fails at test #5 after decoding fixes
- This is a regression introduced by Bug #51 fix

### Known Information
- Failure: Test #5 after 114 cycles
- Final state: `x14 = 0x40000000` (2.0 in single-precision)
- Expected: `x14 = 0x00000000`
- Only one FPU operation visible in debug output (test #2)
- Tests #3 and #4 don't show FPU operations

### Investigation Steps

1. **Compare Before/After Behavior**
   ```bash
   # Check what changed in test behavior
   git show d5a22e0:rtl/core/control.v | grep -A 20 "5'b11000"
   git show HEAD:rtl/core/control.v | grep -A 20 "5'b01000"
   ```

2. **Detailed Debug Trace**
   ```bash
   # Get full debug output for tests #2-5
   env DEBUG_FPU=1 XLEN=32 timeout 10s vvp sim/official-compliance/rv32ud-p-fcvt.vvp 2>&1 > /tmp/fcvt_detailed.log
   
   # Look for all operations between test 2 and 5
   grep -E "(GP_WRITE|CORE.*FPU|FPU.*START|FPU.*DONE|FP_DECODE)" /tmp/fcvt_detailed.log
   ```

3. **Disassemble Test Program**
   ```bash
   # See what instructions are in tests #2-5
   riscv64-unknown-elf-objdump -d tests/official-compliance/rv32ud-p-fcvt.elf | less
   # Search for test labels around PC 0x800001b0 (test #2 location)
   ```

4. **Check Operation Type Mapping**
   - Verify `cvt_op` values match expected operation types
   - Ensure FCVT.S.D → 4'b1000, FCVT.D.S → 4'b1001
   - Check if any instructions incorrectly map to FP↔FP path now

5. **Suspect: Side Effect of funct7[5] Change**
   - The fix uses `funct7[5]` to distinguish FP↔FP vs FP↔INT
   - Could there be other instructions with funct7[5]=0 being misclassified?
   - Check if test #3/#4 have instructions that should execute FPU but don't

### Quick Test Commands
```bash
# Run test with maximum debug
env DEBUG_FPU=1 DEBUG_FPU_CONVERTER=1 XLEN=32 timeout 10s vvp sim/official-compliance/rv32ud-p-fcvt.vvp

# Check if reverting to old logic passes test #5
# (Temporary test - do NOT commit)
```

---

## Secondary Priorities (if time permits)

### 2. rv32ud-p-fdiv - Test #7
- 1 ULP rounding error in division
- Mantissa precision issue in `rtl/core/fp_divider.v`
- Lower priority than regression fix

### 3. rv32ud-p-fmadd - Test #5  
- Incorrect FMA result
- Precision issue in `rtl/core/fp_fma.v`
- Lower priority than regression fix

---

## Test Status Reference

```
RV32D: 66% (6/9 tests)

✓ rv32ud-p-fadd      - Passing
✓ rv32ud-p-fclass    - Passing  
✓ rv32ud-p-fcmp      - Passing
✗ rv32ud-p-fcvt      - REGRESSION: test #5 (was passing)
✓ rv32ud-p-fcvt_w    - Passing (no regression)
✗ rv32ud-p-fdiv      - Pre-existing: test #7 (1 ULP error)
✗ rv32ud-p-fmadd     - Pre-existing: test #5 (precision)
✓ rv32ud-p-fmin      - Passing
✓ rv32ud-p-ldst      - Passing
```

---

## Session Goals

**Must Have:**
1. Identify why fcvt test #5 now fails
2. Fix the regression without breaking fcvt_w
3. Verify RV32D returns to 66%+ pass rate

**Nice to Have:**
4. Document root cause and fix
5. Make progress on fdiv or fmadd if time allows

---

## Files to Review

- `rtl/core/control.v` - Line 434 (funct7[5] condition)
- `rtl/core/fpu.v` - Line 368 (cvt_op assignment)
- `rtl/core/fp_converter.v` - FCVT.S.D/D.S implementation
- `tests/official-compliance/rv32ud-p-fcvt.hex` - Test program

## Reference Documents

- Session 18 notes: `docs/SESSION18_FCVT_DECODING_FIX.md`
- Previous session: `d5a22e0` (last known good for fcvt)
- RISC-V spec: Volume 1, Chapter 11 (F/D Extensions)
