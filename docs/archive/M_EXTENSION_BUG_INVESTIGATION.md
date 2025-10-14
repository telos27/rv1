# M Extension Division-by-Zero Bug Investigation

**Date**: 2025-10-12
**Status**: BUG IDENTIFIED - Pipeline Operand Corruption
**Impact**: M extension tests failing (3/8)

---

## Problem Statement

M extension division tests (DIVU, REM, REMU) failing with division-by-zero returning wrong results:
- **Expected**: `1 / 0 = 0xFFFFFFFF`
- **Actual**: `1 / 0 = 0xFFFFFFF4` (off by 11)

---

## Key Findings

### ✅ Division Unit is CORRECT

Standalone testing confirms `div_unit.v` works perfectly:
```bash
$ vvp sim_div_unit_simple
PASS: DIVU 1/0 = 0xFFFFFFFF
PASS: REMU 5/0 = 5
PASS: DIVU 10/2 = 5
```

**Conclusion**: The bug is NOT in the division logic.

### ❌ Pipeline Provides WRONG Operands

Debug output shows operands are corrupted BEFORE reaching `mul_div_unit`:

```
Test 9 expects: DIVU a4, a1=1, a2=0
Actually receives: operand_a=0x14 operand_b=0xFFFFFFFA
```

Values `0x14` and `0xFFFFFFFA` come from **different tests** (test 4 and test 5):
- Test 4: `li a1, 20` (0x14)
- Test 5: `li a2, -6` (0xFFFFFFFA)
- Test 9: `li a1, 1; li a2, 0; divu a4, a1, a2` ← SHOULD use these values!

**Critical**: NO division-by-zero operations ever reach the division unit. The divisor is never 0 in the debug logs.

---

## Root Cause Analysis

The pipeline is feeding **mixed operands from different instructions** to the M extension unit. This suggests:

1. **Operand Forwarding Bug**: Forwarding logic pulls values from wrong pipeline stages
2. **IDEX Register Corruption**: Values in IDEX being overwritten during M extension hold
3. **Hold Logic Failure**: IDEX hold signal not preventing register updates properly

### Pipeline Behavior During M Extension

When M instruction executes (32+ cycles for division):
- ✅ PC stalled (correct)
- ✅ IFID stalled (correct)
- ✅ IDEX held via `hold_exmem` signal (should be correct)
- ✅ EXMEM held (correct)
- ❌ **But operands to M unit are WRONG**

### Current Operand Path

```
Pipeline → ex_alu_operand_a_forwarded → mul_div_unit.operand_a → [latched] → div_unit.dividend
           ex_rs2_data_forwarded      → mul_div_unit.operand_b → [latched] → div_unit.divisor
```

Problem: `ex_alu_operand_a_forwarded` and `ex_rs2_data_forwarded` are **wires** recomputed every cycle based on forwarding muxes.

---

## Attempted Fixes (Did Not Solve Issue)

### Fix 1: Store Original Dividend in div_unit
- Added `dividend_reg` to latch original dividend value
- **Result**: No improvement

### Fix 2: Operand Latching in mul_div_unit
- Added registers `operand_a_reg`, `operand_b_reg` to latch inputs
- Delayed `start` signal by one cycle
- **Result**: No improvement - operands are ALREADY wrong when first sampled

---

## Debug Evidence

### Test Sequence (rv32um-p-divu test 9)
```assembly
80000238:  li   gp, 9           # Test number
8000023c:  li   a1, 1           # a1 = 1
80000240:  li   a2, 0           # a2 = 0
80000244:  divu a4, a1, a2      # a4 = 1 ÷ 0 (expect 0xFFFFFFFF)
80000248:  li   t2, -1          # t2 = 0xFFFFFFFF
8000024c:  bne  a4, t2, fail    # Check result
```

### Debug Output
```
[MUL_DIV] Latch: operand_a=00000014 operand_b=fffffffa  ← WRONG!
[DIV] Start: dividend=00000014 divisor=fffffffa div_by_zero=0  ← Should be 1/0!
[DIV] Div-by-zero: NEVER TRIGGERED (divisor != 0)
[MUL_DIV] DIV Ready: result=fffffff4  ← Wrong result
```

### Register State at Failure
```
gp = 9          (test number - correct)
a1 = 0x14       (should be 1 - WRONG!)
a2 = 0xfffffffa (should be 0 - WRONG!)
a4 = 0xfffffff4 (result - wrong because inputs are wrong)
```

---

## Next Steps for Debugging

### Immediate Investigation Needed

1. **Trace Forwarding Logic**:
   - Add debug to `forwarding_unit.v` to see what forwarding decisions are made
   - Check if `forward_a` and `forward_b` signals are correct
   - Verify EXMEM/MEMWB values being forwarded

2. **Verify IDEX Hold Logic**:
   - Add debug to show when IDEX is held vs. updated
   - Confirm `idex_rs1_data` and `idex_rs2_data` remain stable during M extension
   - Check `hold_exmem` signal timing

3. **Check M Extension Start Signal**:
   - Verify `m_unit_start` pulses only ONCE
   - Confirm `ex_mul_div_busy` goes high immediately after start
   - Check timing between `start` assertion and operand availability

4. **Waveform Analysis**:
   - Generate VCD for failing test
   - Trace signals: `idex_rs1_data`, `idex_rs2_data`, `ex_alu_operand_a_forwarded`, `ex_rs2_data_forwarded`
   - Look for transitions during M instruction execution

### Potential Solutions

1. **Fix Forwarding for M Extension**:
   - Disable forwarding when M instruction is in EX stage
   - Use only IDEX register values, not forwarded values

2. **Fix IDEX Hold Logic**:
   - Ensure IDEX truly holds during M extension busy period
   - Verify `hold_exmem` prevents IDEX updates

3. **Add Operand Snapshot Register**:
   - Create dedicated operand registers in the core (not mul_div_unit)
   - Latch operands in EX stage before M unit starts
   - Pass stable register values to M unit

---

## Files Modified (Experimental - May Need Reversion)

```
rtl/core/div_unit.v           # Added dividend_reg, debug output
rtl/core/mul_div_unit.v       # Added operand latching, delayed start
```

**Note**: These changes may need to be reverted if the real fix is in the pipeline core logic.

---

## Test Status

### Passing (5/8)
- ✅ DIV (signed division)
- ✅ MUL
- ✅ MULH
- ✅ MULHSU
- ✅ MULHU

### Failing (3/8)
- ❌ DIVU (unsigned division) - Test #9 fails
- ❌ REM (signed remainder) - Test #13 fails
- ❌ REMU (unsigned remainder) - Test #9 fails

---

## Conclusion

The division unit hardware is correct. The bug is a **pipeline operand corruption issue** where the wrong register values are provided to the M extension unit. The operands appear to be mixed from different tests, suggesting a fundamental problem with either:
- Operand forwarding during multi-cycle M operations
- IDEX register hold logic
- Timing of operand capture vs. M unit start signal

**Next session should focus on**: Tracing the pipeline with waveforms or detailed debug output to see exactly where the operand values get corrupted.
