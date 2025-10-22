# Bug #38: FP Multiplier Operand Latching Bug

**Date**: 2025-10-22
**Status**: FIXED ✅
**Impact**: rv32uf-p-recoding now PASSING
**Test Coverage**: RV32UF 10/11 passing (90%, was 81%)

---

## Summary

The fp_multiplier module was not latching input operands when the operation started, causing it to read stale/incorrect values during the UNPACK state. This led to incorrect special case detection (treating 3.0 as zero) and producing NaN instead of -Inf for `3.0 × -Inf`.

---

## Symptoms

### Test Failure
- **Test**: rv32uf-p-recoding
- **Failed at**: Test #2 (and consequently #5)
- **Expected**: `3.0 × -Inf = -Inf (0xff800000)`
- **Actual**: `3.0 × -Inf = NaN (0x7fc00000)`

### Debug Output
```
[FPU] START: op=2 a=40400000 b=ff800000 c=00000000  ← Correct at start
[FP_MUL] UNPACK: operand_a=00000000 operand_b=ff800000  ← Wrong in UNPACK!
[FP_MUL] MULTIPLY: is_zero_a=1 is_inf_b=1  ← Incorrect zero detection
[FPU] DONE: op=2 result=7fc00000 flags=10000  ← NaN (invalid operation)
```

---

## Root Cause

### Timing Issue in State Machine

The fp_multiplier uses a multi-cycle state machine:
```
Cycle N:   IDLE (start asserted, operand_a = 0x40400000)
Cycle N+1: UNPACK (reads operand_a, but it changed to 0x00000000!)
```

**File**: `rtl/core/fp_multiplier.v`

#### Original Code (BROKEN)
```verilog
module fp_multiplier (
  input wire [FLEN-1:0] operand_a,  // Direct wire input
  input wire [FLEN-1:0] operand_b,
  ...
);

// State machine transitions on clock edge
always @(posedge clk) begin
  state <= next_state;  // IDLE → UNPACK
end

// UNPACK state reads operands (one cycle after start)
UNPACK: begin
  sign_a <= operand_a[FLEN-1];  // ← Reads CURRENT wire value, not start value!
  exp_a <= operand_a[FLEN-2:MAN_WIDTH];
  is_zero_a <= (operand_a[FLEN-2:0] == 0);  // ← Got 0x00000000 instead of 0x40400000
  ...
end
```

### Why Operands Changed

The FPU top-level module updates operand wires every cycle based on pipeline forwarding:
1. Cycle N: FPU asserts `start`, `operand_a = 0x40400000` (from f1 register)
2. Cycle N+1: FPU writeback updates f1 register (from previous operation)
3. Cycle N+1: UNPACK state reads `operand_a`, but it now reflects the new f1 value (0x00000000)

---

## Fix

### Solution: Latch Operands in IDLE State

**Modified Code**:
```verilog
// Add latched registers
reg [FLEN-1:0] operand_a_latched, operand_b_latched;

// Capture operands when start is asserted
IDLE: begin
  if (start) begin
    operand_a_latched <= operand_a;
    operand_b_latched <= operand_b;
  end
end

// Use latched values in UNPACK
UNPACK: begin
  sign_a <= operand_a_latched[FLEN-1];  // ← Now stable!
  exp_a <= operand_a_latched[FLEN-2:MAN_WIDTH];
  is_zero_a <= (operand_a_latched[FLEN-2:0] == 0);
  ...
end
```

### Changed Lines
- **Line 48-49**: Added `operand_a_latched` and `operand_b_latched` registers
- **Line 112-117**: Added IDLE state handler to latch operands
- **Line 127-157**: Changed all UNPACK references from `operand_a/b` to `operand_a/b_latched`

---

## Verification

### Test Results After Fix
```
$ env XLEN=32 ./tools/run_official_tests.sh f

rv32uf-p-fadd...               PASSED
rv32uf-p-fclass...             PASSED
rv32uf-p-fcmp...               PASSED
rv32uf-p-fcvt...               PASSED
rv32uf-p-fcvt_w...             PASSED
rv32uf-p-fdiv...               FAILED (fsqrt Bug #37)
rv32uf-p-fmadd...              PASSED
rv32uf-p-fmin...               PASSED
rv32uf-p-ldst...               PASSED
rv32uf-p-move...               PASSED
rv32uf-p-recoding...           PASSED ✅ (was FAILING)

Total:  11
Passed: 10 ✅ (was 9)
Failed: 1
Pass rate: 90% (was 81%)
```

### Debug Output After Fix
```
[FPU] START: op=2 a=40400000 b=ff800000 c=00000000
[FP_MUL] UNPACK: operand_a=40400000 operand_b=ff800000  ← Correct!
[FP_MUL] MULTIPLY: is_zero_a=0 is_inf_b=1  ← Correct!
[FPU] DONE: op=2 result=ff800000 flags=00000  ← -Inf (correct!)
```

---

## Impact Analysis

### Tests Fixed
- ✅ rv32uf-p-recoding (all 7 tests now pass)

### Tests Still Affected
- ❌ rv32uf-p-fdiv (fails at test #11, fsqrt - Bug #37)

### Performance
- No performance impact (added 2 registers, 1 state handler)
- No timing impact (operands already stable before IDLE→UNPACK transition)

---

## Related Bugs

### Same Class As
- **Bug #18**: FP Converter timing bug (non-blocking assignment read in same cycle)
- **Bug #35**: FP Sqrt test_value timing bug (wire vs reg issue)

All three bugs involve reading values before they've been properly latched/registered.

### Next Bug to Fix
- **Bug #37**: FP Sqrt algorithm broken (returns 0x00000000 for all inputs)
  - See: `docs/NEXT_STEPS_SQRT_RECODING.md`
  - Blocks: rv32uf-p-fdiv

---

## Lessons Learned

### Design Pattern Issues
1. **Multi-cycle modules must latch inputs**: Never assume input wires remain stable
2. **Pipeline forwarding creates timing hazards**: Inputs can change mid-operation
3. **State machines need input capture**: Latch in first state, use in subsequent states

### Best Practice
For multi-cycle FPU operations:
```verilog
IDLE: begin
  if (start) begin
    // Capture ALL inputs that will be used in later states
    operand_a_reg <= operand_a;
    operand_b_reg <= operand_b;
    rounding_mode_reg <= rounding_mode;
  end
end

COMPUTE: begin
  // Use registered inputs, not wire inputs
  result <= compute(operand_a_reg, operand_b_reg);
end
```

---

## Files Modified
- `rtl/core/fp_multiplier.v` (15 lines changed)

## Commit
```
Bug #38 Fixed: FP Multiplier Operand Latching

Fixed operand capture timing bug in fp_multiplier module:
- Added operand_a_latched and operand_b_latched registers
- Latch operands in IDLE state when start is asserted
- Use latched values in UNPACK instead of wire inputs

Bug: Multiplier was reading operand wires in UNPACK state (1 cycle after
start), but FPU pipeline forwarding had already changed the wire values,
causing incorrect operand values and special case detection.

Example: 3.0 × -Inf
- Start: operand_a = 0x40400000 (3.0) ✓
- UNPACK: operand_a = 0x00000000 (changed!) ✗
- Result: is_zero_a=1, produced NaN instead of -Inf

Fix ensures operands remain stable throughout multi-cycle operation.

Test Impact:
- rv32uf-p-recoding: PASSING ✅ (was FAILING)
- RV32UF: 10/11 passing (90%, was 81%)

Location: rtl/core/fp_multiplier.v:48-49, 112-117, 127-157
Same bug class as Bug #18 (FP Converter) and Bug #35 (FP Sqrt)

Next: Fix Bug #37 (fsqrt algorithm) to reach 100% RV32UF compliance
```

---

**Status**: RESOLVED ✅
**RV32UF Progress**: 10/11 tests passing (90%)
**Next**: Bug #37 - FP Square Root Algorithm
