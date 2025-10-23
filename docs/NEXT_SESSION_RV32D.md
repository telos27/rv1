# Next Session: RV32D Remaining Issues

## Current Status (Session 17 End)

**RV32D: 6/9 tests passing (66%)**

### ✅ Passing Tests (6)
- rv32ud-p-fclass - Classification
- rv32ud-p-fcmp - Comparison
- rv32ud-p-fcvt_w - FP to INT conversion
- rv32ud-p-fmin - Min/Max
- rv32ud-p-ldst - Load/Store

### ❌ Failing Tests (3)

1. **rv32ud-p-fcvt** - TIMEOUT/ERROR
   - Type: INT to FP conversion (FCVT.D.W, FCVT.D.WU, etc.)
   - Status: Test times out
   - Likely cause: Infinite loop or very long operation in fp_converter.v

2. **rv32ud-p-fdiv** - FAILED
   - Type: FP division (FDIV.D, FSQRT.D)
   - Status: Incorrect results
   - Likely cause: Format handling in fp_divider.v or fp_sqrt.v

3. **rv32ud-p-fmadd** - FAILED
   - Type: Fused multiply-add (FMADD.D, FMSUB.D, FNMADD.D, FNMSUB.D)
   - Status: Incorrect results
   - Likely cause: Format handling in fp_fma.v

## Debugging Strategy for Next Session

### Priority 1: fcvt (Timeout)

**Why first**: Timeouts are usually easier to diagnose than incorrect results.

**Approach**:
1. Add debug output to fp_converter.v to see state machine progression
2. Check if converter enters infinite loop in CONVERT state
3. Look for format-specific issues in INT→FP path (lines 268-401)
4. Check if double-precision exponent calculation is correct

**Likely Bug Locations**:
- `rtl/core/fp_converter.v`: CONVERT state for INT→FP
- Look for: Counter initialization, loop conditions, format-specific paths

### Priority 2: fdiv (Incorrect Results)

**Approach**:
1. Run test with DEBUG_FPU to see which specific division fails
2. Check fp_divider.v UNPACK and PACK stages for format handling
3. Verify exponent bias is correct for double-precision (1023 vs 127)
4. Check GRS bit extraction for fmt=1

**Likely Bug Locations**:
- `rtl/core/fp_divider.v`: UNPACK stage (operand extraction)
- `rtl/core/fp_divider.v`: PACK stage (result assembly)
- `rtl/core/fp_sqrt.v`: Same issues if FSQRT.D is failing

**Reference**: Bug #43 fixes for fp_adder.v show the pattern

### Priority 3: fmadd (Incorrect Results)

**Approach**:
1. Run test with DEBUG_FPU to see which FMA operation fails
2. Check fp_fma.v UNPACK and PACK stages for format handling
3. Verify 3-operand extraction works for double-precision
4. Check exponent alignment and rounding for fmt=1

**Likely Bug Locations**:
- `rtl/core/fp_fma.v`: UNPACK stage
- `rtl/core/fp_fma.v`: ALIGN_C stage (operand C alignment)
- `rtl/core/fp_fma.v`: PACK stage

## Tools Available

### Debug Flags
```bash
env DEBUG_FPU=1 XLEN=32 ./tools/run_official_tests.sh ud <test>
```

### Test Individual Cases
```bash
# Run just one test
env XLEN=32 timeout 30s ./tools/run_official_tests.sh ud fcvt

# Check log
cat /home/lei/rv1/sim/official-compliance/rv32ud-p-fcvt.log
```

### Waveform Analysis
```bash
# If needed, open waveform viewer
gtkwave sim/waves/core_pipelined.vcd
```

## Expected Patterns (from Bug #43)

When Bug #43 was fixed, the pattern for FPU modules was:

### UNPACK Stage
```verilog
// BEFORE (WRONG):
assign exp_a = operand_a[30:23];  // Always 8 bits

// AFTER (CORRECT):
assign exp_a = fmt ? operand_a[62:52] : {3'b0, operand_a[30:23]};
```

### PACK Stage
```verilog
// BEFORE (WRONG):
assign result = {sign, exp_result[7:0], man_result[22:0]};

// AFTER (CORRECT):
assign result = fmt ?
                {sign, exp_result[10:0], man_result[51:0]} :
                {32'hFFFFFFFF, sign, exp_result[7:0], man_result[22:0]};
```

### GRS Bits
```verilog
// BEFORE (WRONG):
assign guard = man[22];

// AFTER (CORRECT):
assign guard = fmt ? man[51] : man[22];
```

## Success Criteria

- **Minimum**: Get fcvt test passing (fixes timeout)
- **Good**: Get 8/9 tests passing (fcvt + one of fdiv/fmadd)
- **Excellent**: Get 9/9 tests passing (100% RV32D compliance!) 🎉

## Time Estimate

- fcvt: 30-60 minutes (timeouts usually quick to fix)
- fdiv: 30-90 minutes (similar to Bug #43 patterns)
- fmadd: 30-90 minutes (similar to Bug #43 patterns)

**Total**: 1.5-4 hours to complete RV32D

## References

- docs/SESSION_2025-10-23_BUG50_FLD_FORMAT_FIX.md (current session)
- docs/BUG_43_FD_MIXED_PRECISION.md (similar format handling bugs)
- docs/RV32D_DEBUG_PLAN.md (systematic debugging approach)

---

**Next Goal**: RV32D 100% (9/9 tests passing) 🎯
