# Bug #44: FMA ADD Stage Mantissa Positioning for Single-Precision

**Date**: 2025-10-22
**Status**: IN PROGRESS - Partially Fixed
**Severity**: HIGH - FMA operations return incorrect results
**Test**: rv32uf-p-fmadd failing at test #5

---

## Summary

The FMA (Fused Multiply-Add) module's ADD stage has incorrect mantissa positioning logic for single-precision operations when FLEN=64. This causes FMA operations to return incorrect results.

**Test Case**: `(1.0 × 2.5) + 1.0` should equal `3.5`, but returns incorrect values.

**Root Cause**: When FLEN=64, mantissas are zero-padded to 53 bits for both single and double precision. The product of two 53-bit values is 106 bits with the leading bit at position ~104. The original code used left-shift-by-5 positioning, but this doesn't account for the padding in single-precision operations.

---

## Timeline of Fixes

### Fix #1: FLW NaN-Boxing (COMPLETED ✅)

**File**: `rtl/core/rv32i_core_pipelined.v`
**Issue**: FLW (load single-precision float) was not NaN-boxing loaded values in the forwarding path.

**Problem**:
```verilog
// Before: wb_fp_data came from memwb_fp_mem_read_data without NaN-boxing
assign wb_fp_data = (memwb_wb_sel == 3'b001) ? memwb_fp_mem_read_data : memwb_fp_result;
```

Loaded values like `0x000000003f800000` (not NaN-boxed) were being forwarded to FMA operand_c.

**Fix** (lines 1897-1902):
```verilog
// NaN-box single-precision loads
wire [`FLEN-1:0] fp_load_data_boxed;
assign fp_load_data_boxed = (`FLEN == 64 && !memwb_fp_fmt) ?
                             {32'hFFFFFFFF, memwb_fp_mem_read_data[31:0]} :
                             memwb_fp_mem_read_data;

assign wb_fp_data = (memwb_wb_sel == 3'b001) ? fp_load_data_boxed : memwb_fp_result;
```

**Impact**: FMA operands now properly NaN-boxed, but FMA still returns wrong results.

---

### Fix #2: FMA Product Positioning (COMPLETED ✅)

**File**: `rtl/core/fp_fma.v`
**Issue**: Product was positioned using left-shift-by-5, which is incorrect for FLEN=64.

**Problem**:
For FLEN=64:
- `man_a = {1, mantissa[22:0], 29'b0}` = 53 bits (24 significant + 29 padding)
- `man_b = {1, mantissa[22:0], 29'b0}` = 53 bits (24 significant + 29 padding)
- `product = man_a × man_b` = 106 bits with leading bit at position ~104

Old code:
```verilog
sum <= (product << 5) + aligned_c;  // WRONG: shifts product to position 109
```

**Fix** (lines 416-424):
```verilog
if (FLEN == 64) begin
  // Shift product RIGHT by 53 to position leading bit at [51]
  product_positioned = product >> 53;
end else begin
  // FLEN=32: product is 48 bits (24×24), leading bit at position 46
  // Shift LEFT by 5 to position at [51]
  product_positioned = product << 5;
end
```

**Impact**: Product now positioned correctly at bit 51.

---

### Fix #3: Aligned_c Positioning (COMPLETED ✅)

**File**: `rtl/core/fp_fma.v`
**Issue**: aligned_c was being positioned for the old left-shift-by-5 scheme.

**Problem**:
Old code added 28 bits of padding then shifted:
```verilog
aligned_c = ({man_c[MAN_WIDTH:0], 28'b0} >> exp_diff);  // WRONG for FLEN=64
```

This positioned man_c's leading bit at position 80, not 51.

**Fix** (lines 384-416):
```verilog
if (exp_prod >= exp_c) begin
  exp_result = exp_prod;
  exp_diff = exp_prod - exp_c;

  if (FLEN == 64)
    aligned_c = (man_c >> exp_diff);  // man_c already has leading bit at 52
  else
    aligned_c = ({man_c[MAN_WIDTH:0], 28'b0} >> exp_diff);  // FLEN=32
end else begin
  exp_result = exp_c;
  exp_diff = exp_c - exp_prod;

  if (exp_diff > (2*MAN_WIDTH + 6))
    product = {1'b0, {(2*MAN_WIDTH+3){1'b0}}, 1'b1};
  else
    product = product >> exp_diff;

  if (FLEN == 64)
    aligned_c = man_c;
  else
    aligned_c = {man_c, 28'b0};
end
```

**Impact**: Both product and aligned_c now correctly positioned with leading bits at ~51.

---

### Fix #4: NORMALIZE Stage Overflow Detection (COMPLETED ✅)

**File**: `rtl/core/fp_fma.v`
**Issue**: NORMALIZE stage was checking for overflow at wrong bit position.

**Problem**:
Old code checked `sum[(2*MAN_WIDTH+6)]` (bit 110 for FLEN=64), but with new positioning the overflow bit is at position 52.

**Fix** (lines 478-501):
```verilog
// Check for overflow at bit 52 (one position above normalized 51)
else if (FLEN == 64 && sum[52]) begin
  sum <= sum >> 1;
  exp_result <= exp_result + 1;
  if (!fmt_latched) begin
    guard <= sum[29];
    round <= sum[28];
    sticky <= |sum[27:0];
  end else begin
    guard <= sum[0];
    round <= 1'b0;
    sticky <= 1'b0;
  end
end
// For FLEN=32: Check overflow at old position
else if (FLEN == 32 && sum[(2*MAN_WIDTH+6)]) begin
  sum <= sum >> 1;
  exp_result <= exp_result + 1;
  guard <= sum[0];
  round <= 1'b0;
  sticky <= 1'b0;
end
```

**Impact**: Overflow correctly detected and handled.

---

### Fix #5: NORMALIZE Stage Normalized Detection (COMPLETED ✅)

**File**: `rtl/core/fp_fma.v`
**Issue**: Normalized detection was checking bit 109 instead of bit 51.

**Fix** (lines 502-529):
```verilog
// Check if leading 1 is at bit 51 (normalized for FLEN=64)
else if (FLEN == 64 && sum[51]) begin
  if (!fmt_latched) begin
    // Single-precision: GRS at bits [28:26]
    guard <= sum[28];
    round <= sum[27];
    sticky <= |sum[26:0];
  end else begin
    // Double-precision: GRS needs proper extraction
    guard <= sum[0];
    round <= 1'b0;
    sticky <= 1'b0;
  end
end
// For FLEN=32: Check normalized position at old bit
else if (FLEN == 32 && sum[(2*MAN_WIDTH+5)]) begin
  guard <= sum[MAN_WIDTH+4];
  round <= sum[MAN_WIDTH+3];
  sticky <= |sum[MAN_WIDTH+2:0];
end
// Leading 1 below normalized position - shift left
else begin
  sum <= sum << 1;
  exp_result <= exp_result - 1;
end
```

**Impact**: Normalization now works correctly for new bit positions.

---

### Fix #6: ROUND Stage Mantissa Extraction (COMPLETED ✅)

**File**: `rtl/core/fp_fma.v`
**Issue**: ROUND stage was extracting mantissa from bits [108:86] instead of [50:28].

**Fix** (lines 568-578):
```verilog
if (FLEN == 64 && !fmt_latched) begin
  // Single-precision: Extract 23-bit mantissa from sum[50:28]
  // Leading bit is implicit 1 at position 51
  if (round_up_comb) begin
    result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
               sum[50:28] + 1'b1};
  end else begin
    result <= {32'hFFFFFFFF, sign_result, exp_result[7:0],
               sum[50:28]};
  end
end
```

**Impact**: Mantissa correctly extracted from sum.

---

## Current Status

### Progress
- ✅ FLW NaN-boxing fixed
- ✅ FMA product positioning fixed
- ✅ FMA aligned_c positioning fixed
- ✅ NORMALIZE overflow detection fixed
- ✅ NORMALIZE normalized detection fixed
- ✅ ROUND mantissa extraction fixed

### Test Results
**Before fixes**: `(1.0 × 2.5) + 1.0` returned various incorrect values (1.0, 2.5, 4.0)
**Current**: Returns 4.5 instead of 3.5
**Expected**: 3.5

### Remaining Issue

The current result is **4.5** (exp=129, mantissa=0x100000) instead of **3.5** (exp=128, mantissa=0x600000).

**Analysis**:
- Exponent is 1 too high (129 vs 128)
- Mantissa is `0x100000` (bit 20 set) instead of `0x600000` (bits 22-21 set)

**Debug output**:
```
sum_will_be = 0x12000000000000  (bits 52, 49 set)
sum (after NORMALIZE) = 0x9000000000000  (bits 51, 48 set)
exp_result = 129
```

The sum `0x12000000000000` has:
- Bit 52 set → overflow detected
- Bit 49 set

After overflow handling (shift right by 1):
- Bit 52 → bit 51
- Bit 49 → bit 48
- exp += 1 (128 → 129)

Resulting in sum `0x9000000000000` with exp=129.

**Expected behavior**:
For result 3.5 = 1.75 × 2^1:
- exp = 128 (bias 127 + 1)
- mantissa = 0.110000... = 0x600000

But we're getting 4.5 = 1.125 × 2^2:
- exp = 129 (bias 127 + 2)
- mantissa = 0.001000... = 0x100000

**Hypothesis**: The sum before overflow had the wrong bit pattern. Let me trace through:
- Product: 2.5 with exp=128 → leading bit at 51, bits [51,49] = 10.1 binary = 2.5
- Aligned C: 1.0 with exp=127, shifted right by 1 → leading bit at 51, bit [51] = 1.0

Wait, both have leading bits at 51! That's the problem. When aligned_c is shifted right by exp_diff=1, its leading bit moves from 52 to 51. But the product ALSO has leading bit at 51. So we're adding:

```
Product:    bits [51, 49] = 101000... (2.5 in binary with leading 1 at bit 51)
Aligned C:  bit  [51]     = 100000... (1.0 in binary, but should be 0.5!)
```

The issue is that aligned_c represents 1.0 with exponent 127, but after shifting right by 1 bit, it should represent 0.5 (not 1.0) when aligned with exponent 128!

**Root cause**: The alignment is treating exponents incorrectly. When we set `exp_result = exp_prod = 128` and shift aligned_c right by 1, we're converting:
- Original: 1.0 × 2^127
- After shift: Should be 0.5 × 2^128 (equivalent to 1.0 × 2^127)

But the positioning puts the leading bit at 51, which represents 1.0, not 0.5!

---

## Next Steps

1. **Re-examine alignment logic**: The current approach of positioning both at bit 51 may be fundamentally wrong. Need to ensure that:
   - Product at exp=128 with leading bit at 51 represents correct value
   - Aligned_c at exp=127, shifted to exp=128, represents correct fractional value

2. **Alternative approach**: Instead of aligning both at bit 51, consider:
   - Keep product at bit 51 for exp_result
   - Shift aligned_c such that its VALUE (not just bit position) aligns correctly

3. **Verify GRS extraction**: Guard, round, sticky bits may need adjustment

---

## Files Modified

1. `rtl/core/rv32i_core_pipelined.v` - Added FLW NaN-boxing
2. `rtl/core/fp_fma.v` - Comprehensive positioning fixes (6 changes)

---

## Related Issues

- Bug #43: F+D Mixed Precision Support (COMPLETE)
- This bug was discovered while testing fmadd after Bug #43 fixes

---

## Testing

**Test command**:
```bash
timeout 60s ./tools/run_single_test.sh rv32uf-p-fmadd
```

**Debug command**:
```bash
timeout 60s ./tools/run_single_test.sh rv32uf-p-fmadd DEBUG_FPU
```

---

*Investigation ongoing - FMA module requires deeper analysis of alignment and positioning logic.*
