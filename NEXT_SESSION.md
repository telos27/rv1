# Next Session: Bug #43 - F+D Mixed Precision Support (Phase 1)

**Last Session**: 2025-10-22
**Status**: Root cause identified, 1/10 modules fixed
**Priority**: 🔥 CRITICAL - All RV32F tests broken (1/11 passing)

---

## Quick Context

### What Happened
The RV32D refactoring (Bugs #27 & #28) successfully widened FP registers to 64 bits but broke all single-precision FP tests. The FP modules assume `FLEN` directly maps to the precision being operated on, rather than checking the `fmt` signal to distinguish between single (32-bit) and double (64-bit) precision.

### Current Status
- **RV32UF**: 1/11 (9%) - only ldst passes ❌
- **RV32UD**: 1/9 (11%) - fclass passes ✅
- **Root cause**: FP modules extract sign/exponent/mantissa from wrong bit positions
- **Progress**: fp_sign.v fixed ✅, 9 modules remaining

---

## Immediate Next Steps (Phase 1: 2-3 hours)

Fix the simple bit-extraction modules that don't have complex state machines:

### 1. Fix fp_compare.v (45 min)

**Issue**: Extracts sign/exponent/mantissa from FLEN-relative positions [63:0] instead of [31:0] for single-precision.

**Fix**:
```verilog
// Add fmt input
input wire fmt,  // 0: single-precision, 1: double-precision

// Extract fields conditionally
generate
  if (FLEN == 64) begin : g_flen64
    assign sign_a = fmt ? operand_a[63] : operand_a[31];
    assign sign_b = fmt ? operand_b[63] : operand_b[31];
    assign exp_a = fmt ? operand_a[62:52] : operand_a[30:23];
    assign exp_b = fmt ? operand_b[62:52] : operand_b[30:23];
    assign man_a = fmt ? operand_a[51:0] : operand_a[22:0];
    assign man_b = fmt ? operand_b[51:0] : operand_b[22:0];
  end else begin : g_flen32
    // FLEN=32: only single-precision
    assign sign_a = operand_a[31];
    assign sign_b = operand_b[31];
    assign exp_a = operand_a[30:23];
    assign exp_b = operand_b[30:23];
    assign man_a = operand_a[22:0];
    assign man_b = operand_b[22:0];
  end
endgenerate
```

**Update fpu.v instantiation** (line ~280):
```verilog
fp_compare #(.FLEN(FLEN)) u_fp_compare (
  .operand_a(operand_a),
  .operand_b(operand_b),
  .operation(compare_op),
  .fmt(fmt),              // ← ADD THIS
  .result(compare_result),
  .flag_nv(compare_flag_nv)
);
```

**Test**:
```bash
env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fcmp
```

### 2. Fix fp_classify.v (30 min)

**Issue**: Same as fp_compare - extracts from wrong bit positions.

**Fix**: Similar pattern - add `fmt` input and conditional extraction.

**Files to modify**:
- rtl/core/fp_classify.v: Add fmt input, fix extraction (lines 21-23)
- rtl/core/fpu.v: Pass fmt to fp_classify (line ~290)

**Test**:
```bash
env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fclass
```

### 3. Fix fp_minmax.v (45 min)

**Issue**: Min/max operations likely compare wrong fields or extract wrong sign bits.

**Need to check first**:
```bash
grep -n "operand.*\[" rtl/core/fp_minmax.v
```

**Fix**: Add fmt input, fix any bit extraction.

**Test**:
```bash
env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf fmin
```

### 4. Verify Phase 1 Progress

After fixing these 3 modules, test results should improve:
```bash
env XLEN=32 ./tools/run_official_tests.sh uf
```

**Target**: 4-5 tests passing (ldst, fcmp, fclass, fmin, move)

---

## Key Files

- **Main bug doc**: `docs/BUG_43_FD_MIXED_PRECISION.md` - Complete analysis and plan
- **Reference implementation**: `rtl/core/fp_sign.v` - Already fixed, use as template
- **FPU instantiations**: `rtl/core/fpu.v` - Lines 258-300 (module instantiations)

---

## Testing Commands

```bash
# Single test
env XLEN=32 timeout 10s ./tools/run_official_tests.sh uf <test_name>

# Full F-extension suite
env XLEN=32 ./tools/run_official_tests.sh uf

# Check for undefined values
timeout 2s vvp sim/official-compliance/rv32uf-p-<test>.vvp 2>&1 | grep -i "x\|undef"

# View waveform (if needed)
gtkwave sim/waves/core_pipelined.vcd
```

---

## Success Criteria - Phase 1

- [ ] fp_compare.v: Added fmt input, fixed bit extraction
- [ ] fp_classify.v: Added fmt input, fixed bit extraction
- [ ] fp_minmax.v: Added fmt input, fixed bit extraction
- [ ] fpu.v: Updated all 3 instantiations to pass fmt
- [ ] Tests passing: fcmp, fclass, fmin, move (4-5 total)
- [ ] No test timeouts
- [ ] Committed with clear message

---

## Future Sessions

**Phase 2** (Sessions 2-4): Arithmetic modules - fp_adder, fp_multiplier, fp_divider, fp_sqrt
**Phase 3** (Session 5): fp_converter, fp_fma
**Phase 4** (Session 6): Testing & verification

**Final Goal**: RV32UF 11/11 ✅, RV32UD 9/9 ✅

---

## Important Notes

⚠️ **Don't test full suite until Phase 1 complete** - arithmetic ops will still fail
⚠️ **Use timeouts** - Some tests may hang with X values
⚠️ **Commit incrementally** - After each module fix

📚 **Pattern to follow**: See fp_sign.v for reference implementation
🎯 **Start with**: fp_compare.v (most straightforward)

---

**Ready to start?** Open `rtl/core/fp_compare.v` and add the fmt input!

🤖 Generated with [Claude Code](https://claude.com/claude-code)
