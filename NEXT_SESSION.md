# Next Session: Bug #43 - F+D Mixed Precision (Phase 2 Continued)

**Last Session**: 2025-10-22 (late PM)
**Status**: fp_adder COMPLETE with critical GRS fix, 7/11 tests passing (63%)
**Priority**: 🔥 HIGH - 4 tests still failing

---

## Current Status (2025-10-22 Session 10)

### FPU Compliance: 7/11 tests (63%) 🎉 +1 test fixed!

- ✅ **fadd** - **PASSING** 🆕 (critical GRS bug fixed!)
- ✅ **fclass** - PASSING
- ✅ **fcmp** - PASSING
- ✅ **fcvt** - PASSING
- ⚠️ **fcvt_w** - FAILING (needs investigation)
- ⚠️ **fdiv** - FAILING (needs fp_sqrt + fp_divider fixes)
- ⚠️ **fmadd** - FAILING (needs fp_fma fix)
- ✅ **fmin** - PASSING
- ✅ **ldst** - PASSING
- ⏱️ **move** - TIMEOUT (undefined values, needs investigation)
- ✅ **recoding** - PASSING

## Session 10 Summary (2025-10-22 late PM)

**🎉 MAJOR BREAKTHROUGH: Found and fixed CRITICAL GRS extraction bug!**

### The Problem
fp_adder.v was computing FADD/FSUB operations but producing wrong rounding results:
- **Symptom**: Test #7 failing with result `0xc49a3fff` instead of `0xc49a4000` (-1234.0)
- **Root Cause**: NORMALIZE stage extracting GRS bits from wrong positions!

### The Bug
For single-precision in FLEN=64, after computation:
```
sum[55:0] = {implicit[55], mantissa[54:32], padding[31:0]}
```

**WRONG (old code)**:
```verilog
guard <= sum[2];   // Always 0 for single-precision!
round <= sum[1];   // Always 0!
sticky <= sum[0];  // Always 0!
```

**CORRECT (fixed)**:
```verilog
guard <= sum[31];        // First discarded bit
round <= sum[30];        // Second discarded bit
sticky <= |sum[29:0];    // OR of all remaining bits
```

The padding region [31:0] contains the remainder bits that determine rounding!

### Technical Wins:

**fp_adder.v (3 fixes)**:
1. **NORMALIZE stage**: Fixed GRS extraction for single-precision
   - GRS now at bits [31:29] instead of [2:0]
   - Applied to all normalization paths (no shift, shift-1, shift-2)
2. **ROUND stage**: Format-aware LSB for RNE tie-breaking
   - LSB = normalized_man[32] for single-precision (not bit [3])
3. **Debug output**: Enhanced to show both old LSB and new lsb_bit

**fp_multiplier.v (1 fix)**:
4. **ROUND stage**: Format-aware LSB for RNE tie-breaking
   - LSB = normalized_man[29] for single-precision (not bit [0])

### Modules Status:
✅ **Phase 1 Complete** (4/4):
1. fp_sign.v
2. fp_compare.v
3. fp_classify.v
4. fp_minmax.v

✅ **Phase 2 Partial** (3/6):
5. fp_adder.v ✅ **COMPLETE** (GRS + LSB + mantissa extraction all fixed!)
6. fp_multiplier.v (LSB fix applied, fmt handling done)
7. fp_converter.v (fmt handling done)

❌ **Phase 2 Remaining** (3/6):
8. fp_sqrt.v - Blocks fdiv test
9. fp_divider.v - Blocks fdiv test
10. fp_fma.v - Blocks fmadd test

---

## Next Session Priority

### Option 1: Fix fp_divider.v and fp_sqrt.v (Recommended) ⭐
**Why**: Blocks fdiv test, same GRS extraction bug likely present
**Time**: 2-3 hours
**Impact**: Should unlock fdiv test → 8/11 (72%)

**Approach**:
- Apply same GRS fix pattern from fp_adder
- Check NORMALIZE stage for GRS extraction
- Check ROUND stage for LSB position
- Test incrementally

### Option 2: Fix fp_fma.v
**Why**: Blocks fmadd test
**Time**: 1-2 hours
**Impact**: Should unlock fmadd → 8/11 (72%)

**Note**: FMA combines multiplier + adder, may inherit fixes automatically

### Option 3: Investigate fcvt_w and move failures
**Why**: Understand remaining edge cases
**Time**: 1-2 hours per test
**Impact**: May reveal additional issues

---

## Key Lessons Learned

### The GRS Bug Pattern

For single-precision in FLEN=64, mantissas have 29-bit zero-padding at LSBs:
```
aligned_man[55:0] = {implicit, mantissa[23-bit], padding[29-bit], GRS[3-bit]}
                  = {bit 55, bits 54-32, bits 31-3, bits 2-0}
```

After computation and normalization:
- **Mantissa result**: Extract from bits [54:32]
- **GRS for rounding**: Extract from bits [31:29] (NOT [2:0]!)
- **LSB for RNE**: Use bit [32] (NOT bit [3]!)

**Why bit [31:29]?**
- When we extract mantissa[54:32], we discard bits [31:0]
- Guard = first discarded bit = sum[31]
- Round = second discarded bit = sum[30]
- Sticky = OR of all remaining bits = |sum[29:0]

### Debug Strategy

1. **Add detailed debug output** - Print G, R, S, LSB values
2. **Check intermediate values** - Don't trust final result alone
3. **Trace bit positions** - Draw diagrams of data layout at each stage
4. **Compare with spec** - Verify against IEEE 754 rounding rules

### Rounding Verification

For RNE (Round to Nearest, Even):
```
round_up = G && (R || S || LSB)
```

Test case: `-1235.1 + 1.1 = -1234.0`
- With wrong GRS (0,0,0): round_up = 0 → Result = 0xc49a3fff ❌
- With correct GRS (1,1,1): round_up = 1 → Result = 0xc49a4000 ✅

---

## Testing Commands

```bash
# Test specific module
timeout 60s ./tools/run_single_test.sh rv32uf-p-<test> DEBUG_FPU

# Full suite
timeout 180s ./tools/run_hex_tests.sh rv32uf

# Check specific test failure
timeout 60s ./tools/run_single_test.sh rv32uf-p-<test> | tail -30
```

---

## Key Files

- **Main bug doc**: `docs/BUG_43_FD_MIXED_PRECISION.md`
- **Fixed modules**: `rtl/core/fp_adder.v`, `rtl/core/fp_multiplier.v`
- **Next targets**: `rtl/core/fp_divider.v`, `rtl/core/fp_sqrt.v`, `rtl/core/fp_fma.v`

---

## Success Criteria - Phase 2 Complete

- [ ] fp_divider.v: Fixed GRS extraction and LSB position
- [ ] fp_sqrt.v: Fixed GRS extraction and LSB position
- [ ] fp_fma.v: Verified/fixed GRS and LSB handling
- [ ] fdiv test: PASSING (includes FDIV + FSQRT)
- [ ] fmadd test: PASSING (includes FMADD/FMSUB/FNMADD/FNMSUB)
- [ ] Tests passing: 9-10/11 (81-90%)
- [ ] Commit with clear message documenting GRS bug fix

---

**Ready to continue?** Start with `fp_divider.v` and `fp_sqrt.v` - apply the same GRS extraction pattern!

🤖 Generated with [Claude Code](https://claude.com/claude-code)
