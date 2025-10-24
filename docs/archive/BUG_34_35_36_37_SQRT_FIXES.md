# FPU Bugs #34-#37: Square Root Algorithm Issues

**Date**: 2025-10-22
**Status**: ⚠️ PARTIALLY FIXED (mantissa extraction fixed, algorithm still broken)
**Severity**: CRITICAL
**Impact**: rv32uf-p-fdiv and rv32uf-p-recoding tests failing

---

## Summary

The `fp_sqrt` module has multiple bugs preventing correct square root computation. Three bugs have been fixed (mantissa extraction, timing, width overflow), but the core algorithm remains broken and needs complete rewrite.

**Test Status**:
- RV32UF: 9/11 passing (81%)
- Failing: rv32uf-p-fdiv, rv32uf-p-recoding (both depend on fsqrt)

**Test Case**: sqrt(π) = sqrt(3.14159265)
- Input: 0x40490FDB
- Expected: 0x3FE2DFC5 ≈ 1.7724539
- **Before fixes**: 0x7F000FFF (wrong exponent, wrong mantissa)
- **After Bug #34**: 0x3F800FFF (correct exponent, wrong mantissa)
- **After Algorithm rewrite**: 0x00000000 (returns zero)

---

## Bug #34: Sqrt Mantissa Extraction Error ✅ FIXED

**Location**: `rtl/core/fp_sqrt.v:264-266`

**Root Cause**: Extracted 24 bits instead of 23 bits for IEEE 754 mantissa
- Same issue as Bug #1 in fp_adder.v (mantissa includes implicit leading 1)

**Before**:
```verilog
if (round_up) begin
  result <= {1'b0, exp_result, root[MAN_WIDTH+3:3] + 1'b1};  // [26:3] = 24 bits
end else begin
  result <= {1'b0, exp_result, root[MAN_WIDTH+3:3]};
end
```

**After**:
```verilog
if (round_up) begin
  result <= {1'b0, exp_result, root[MAN_WIDTH+2:3] + 1'b1};  // [25:3] = 23 bits
end else begin
  result <= {1'b0, exp_result, root[MAN_WIDTH+2:3]};
end
```

**Impact**: Fixed exponent from 0xFE (254) to 0x7F (127) - correct!

---

## Bug #35: Sqrt Test Value Timing Bug ✅ FIXED

**Location**: `rtl/core/fp_sqrt.v:57,63-68` (original lines 209-221)

**Root Cause**: `test_value` used non-blocking assignment (`<=`), then read in same cycle
- Same class of bug as Bug #18 in fp_converter.v
- Sequential assignment evaluated one cycle late, causing wrong comparisons

**Before**:
```verilog
reg [MAN_WIDTH+4:0] test_value;

// Inside COMPUTE state:
test_value <= ((root << 1) + 1'b1) * ((root << 1) + 1'b1);  // <=

if (test_value <= radicand) begin  // Uses OLD value!
  ...
end
```

**After**:
```verilog
wire [MAN_WIDTH+4:0] ac;
wire [MAN_WIDTH+4:0] test_val;
wire test_positive;

assign ac = (remainder << 1) | radicand_shift[(MAN_WIDTH+4)*2-1];
assign test_val = ac - ({root, 1'b1});
assign test_positive = (test_val[MAN_WIDTH+4] == 1'b0);
```

**Impact**: Timing bug fixed, but algorithm still broken

---

## Bug #36: Sqrt Test Value Width Overflow ✅ FIXED

**Location**: `rtl/core/fp_sqrt.v:57` (original declaration)

**Root Cause**: `test_value` was 28 bits, but stored squared value (up to 56 bits)
- `(root << 1) + 1` can be 28 bits
- Squaring it produces up to 56 bits
- Multiplication result overflowed, causing incorrect comparisons

**Before**:
```verilog
wire [MAN_WIDTH+4:0] test_value;  // 28 bits for SP
assign test_value = ((root << 1) + 1'b1) * ((root << 1) + 1'b1);  // Up to 56 bits!
```

**After** (with algorithm rewrite):
```verilog
wire [MAN_WIDTH+4:0] test_val;  // 28 bits
assign test_val = ac - ({root, 1'b1});  // Subtraction, not squaring
```

**Impact**: Changed algorithm to avoid squaring, uses subtraction instead

---

## Bug #37: Sqrt Algorithm Fundamentally Broken ⚠️ NOT FIXED

**Location**: `rtl/core/fp_sqrt.v:165-236` (entire COMPUTE state)

**Root Cause**: Original algorithm incorrect, attempted rewrite still buggy

### Original Algorithm (Broken)
```verilog
test_value = ((root << 1) + 1)²
if (test_value <= radicand) then
  root = (root << 1) | 1
  radicand = radicand - test_value
else
  root = root << 1
```

**Problems**:
1. Squaring operation causes overflow (Bug #36)
2. Logic doesn't match standard digit-by-digit sqrt
3. Radicand modified incorrectly

### Attempted Rewrite (Still Broken)
Implemented standard digit-by-digit algorithm:
```verilog
ac = (remainder << 1) | next_bit_from_radicand
test_val = ac - (2*root + 1)
if (test_val >= 0) then
  remainder = test_val
  root = (root << 1) | 1
else
  remainder = ac
  root = root << 1
```

**Current Result**: Returns 0x00000000 instead of correct value

**Likely Issues**:
1. Radicand initialization incorrect
2. Bit extraction from radicand wrong
3. Iteration count or termination condition wrong
4. Result normalization/scaling incorrect

---

## Test Results

### Before Any Fixes
```
Input:  sqrt(π) = sqrt(0x40490FDB)
Output: 0x7F000FFF
  Sign: 0, Exp: 0xFE (254), Man: 0x000FFF
  Value: ~1.7e38 (completely wrong)
```

### After Bug #34 (Mantissa Fix)
```
Output: 0x3F800FFF
  Sign: 0, Exp: 0x7F (127), Man: 0x000FFF
  Value: ~1.0005 (exponent correct, mantissa wrong)
```

### After Algorithm Rewrite
```
Output: 0x00000000
  Sign: 0, Exp: 0x00, Man: 0x000000
  Value: +0.0 (algorithm returns zero)
```

### Expected
```
Output: 0x3FE2DFC5
  Sign: 0, Exp: 0x7F (127), Man: 0x62DFC5
  Value: ~1.7724539 ✓
```

---

## Compliance Test Impact

### rv32uf-p-fdiv
- Tests 2-4: fdiv operations (passing)
- Test 5: `fsqrt.s fa3, fa0` with π → **FAILS**
- Tests 6-8: More fsqrt operations
- **Status**: Fails at test #5 (gp=0x0B)

### rv32uf-p-recoding
- Status unknown, likely also depends on fsqrt
- **Status**: FAILED

### Overall RV32UF Status
- **9/11 tests passing (81%)**
- ✅ Passing: fadd, fclass, fcmp, fcvt, fcvt_w, fmadd, fmin, ldst, move
- ❌ Failing: fdiv, recoding

---

## Next Steps

The sqrt algorithm needs complete rewrite. Options:

### Option 1: Debug Current Implementation
- Add comprehensive debug output
- Trace algorithm step-by-step
- Fix bit extraction and accumulation logic
- **Effort**: Medium (4-6 hours)
- **Risk**: May have multiple subtle bugs

### Option 2: Reference Implementation
- Use proven algorithm from Berkeley hardfloat
- Or adapt from working open-source FPU
- **Effort**: Medium (3-5 hours)
- **Risk**: Low (algorithm proven)

### Option 3: Newton-Raphson Iteration
- Use iterative approximation: `x_{n+1} = (x_n + N/x_n) / 2`
- Requires FP division (which works) and FP addition (which works)
- **Effort**: Medium (4-6 hours)
- **Risk**: Medium (convergence and rounding issues)

### Option 4: Lookup Table + Refinement
- Use small lookup table for initial approximation
- Refine with 1-2 Newton-Raphson iterations
- **Effort**: High (6-8 hours)
- **Risk**: Medium (table size, accuracy)

---

## Recommended Approach

**Short term**: Reference implementation (Option 2)
- Fastest path to working sqrt
- Proven correct
- Can optimize later

**Long term**: Optimize for area/speed if needed

---

## Files Modified

- `rtl/core/fp_sqrt.v`: All changes
- `tests/asm/test_fsqrt_simple.s`: Created for testing (not working)

---

## Related Documentation

- **Bug #1** (fp_adder.v): Same mantissa extraction error
- **Bug #18** (fp_converter.v): Same timing bug (blocking vs non-blocking)
- **Bug #11** (fp_divider.v): Counter initialization (different but related)

---

## Code Changes Summary

**Bugs #34-#36 Fixed**:
- Mantissa extraction: `[26:3]` → `[25:3]`
- Timing: `reg` with `<=` → `wire` with `assign`
- Width: Removed squaring operation

**Bug #37 Attempted Fix**:
- Rewrote COMPUTE state with digit-by-digit algorithm
- Changed from 2-bits-per-cycle to 1-bit-per-cycle
- Added proper remainder tracking
- **Result**: Still broken, returns zero

**Commit Status**: Ready to commit partial fixes with documentation

---

**Next session should**: Implement working sqrt algorithm using reference or proven method.
