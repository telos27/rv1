# Bug #39: FSQRT Counter Initialization Error

**Date**: 2025-10-22
**Status**: ✅ FIXED (Partial - see Bug #40)
**Impact**: FSQRT returned 0 for all inputs → Now works for perfect squares
**Location**: `rtl/core/fp_sqrt.v:205`

---

## Summary

The floating-point square root (FSQRT) module had a critical counter initialization bug that caused it to skip the computation phase entirely, returning 0 for all inputs. After fixing, the algorithm now correctly computes square roots for perfect squares (e.g., 4.0, 9.0) but still has precision issues for non-perfect squares (see Bug #40).

---

## Root Cause

In the UNPACK state, the `sqrt_counter` was initialized to:
```verilog
sqrt_counter <= SQRT_CYCLES;  // = (MAN_WIDTH/2) + 4 = 15
```

But the COMPUTE state checked for:
```verilog
if (sqrt_counter == (MAN_WIDTH+4)-1) begin  // = 26
```

Since 15 ≠ 26, the initialization block never executed, and the algorithm went straight to iteration with:
- Uninitialized radicand (0)
- Uninitialized root (0)
- Uninitialized remainder (0)

This caused all iterations to operate on zeros, producing a final result of 0.

---

## The Fix

### Changed Line 205
**Before:**
```verilog
sqrt_counter <= SQRT_CYCLES;  // Wrong: 15
```

**After:**
```verilog
// Need MAN_WIDTH+4 bits for mantissa (24) + GRS (3) + 1 extra = 28 bits
sqrt_counter <= (MAN_WIDTH + 4) - 1;  // Correct: 26
```

### Additional Fix (Line 251)
The initialization block was re-setting the counter to 26, creating an infinite loop. Fixed by decrementing:

**Before:**
```verilog
sqrt_counter <= (MAN_WIDTH + 4) - 1;  // 26, loops forever
```

**After:**
```verilog
// Decrement counter to start iterations (move from 26 to 25)
sqrt_counter <= (MAN_WIDTH + 4) - 2;  // 25, breaks loop
```

---

## Test Results

### Before Fix
```
sqrt(4.0) = 0x40800000  →  0x00000000 (0.0) ❌
sqrt(9.0) = 0x41100000  →  0x00000000 (0.0) ❌
sqrt(π)   = 0x40490FDB  →  0x00000000 (0.0) ❌
```

### After Fix
```
sqrt(4.0) = 0x40800000  →  0x40000000 (2.0) ✅
sqrt(9.0) = 0x41100000  →  0x40400000 (3.0) ✅
sqrt(π)   = 0x40490FDB  →  0x3FC00000 (1.5) ❌ (should be 1.7724539)
```

### Official Test Impact
- **Before**: rv32uf-p-fdiv FAILING (gp=11, all fsqrt returned 0)
- **After**: rv32uf-p-fdiv STILL FAILING (gp=11, precision issue - see Bug #40)
- **RV32UF Progress**: 10/11 passing (90%)

---

## Debugging Process

### Initial Symptoms
1. All FSQRT operations returned 0x00000000
2. Algorithm was completing (no hang) but with wrong result
3. Debug output showed state transitions: IDLE→UNPACK→COMPUTE→NORMALIZE→ROUND→DONE
4. But no SQRT_INIT or SQRT_ITER debug messages appeared

### Investigation Steps
1. **Added debug output** to trace state transitions and register values
2. **Discovered state machine was skipping directly** from COMPUTE init check to iterations
3. **Traced counter values**:
   - UNPACK set counter to 15
   - COMPUTE checked for counter == 26
   - Check failed, went to iteration logic with uninitialized registers
4. **Identified mismatch** between `SQRT_CYCLES` (15) and `(MAN_WIDTH+4)-1` (26)
5. **Fixed initialization** and discovered secondary bug (infinite loop at init)
6. **Fixed secondary bug** by decrementing counter after init

### Key Insight
The `SQRT_CYCLES` parameter was defined for a **2-bits-per-iteration algorithm** (radix-4):
```verilog
localparam SQRT_CYCLES = (MAN_WIDTH / 2) + 4;  // Iterations needed (2 bits per cycle)
```

But the actual implementation uses **1-bit-per-iteration** (radix-2), requiring 27 iterations not 15!

---

## Related Issues

### Bug #40: FSQRT Precision for Non-Perfect Squares (OPEN)
After fixing Bug #39, a new issue emerged:
- Perfect squares (4.0, 9.0, 16.0, etc.) compute correctly
- Non-perfect squares (π, 2.0, 3.5, etc.) have precision errors
- Root cause: Algorithm only accepts first bit, rejects all others
- **Status**: Requires algorithm rewrite (see BUG_40_FSQRT_PRECISION.md)

---

## Files Modified

```
rtl/core/fp_sqrt.v:
  - Line 205: Fixed sqrt_counter initialization in UNPACK
  - Line 251: Fixed sqrt_counter in COMPUTE initialization
  - Lines 112-152: Added comprehensive debug output
```

---

## Testing Commands

```bash
# Create test program
cat > tests/asm/test_fsqrt_simple.s << 'EOF'
.section .text
.globl _start
_start:
    # Test 1: sqrt(4.0) = 2.0
    li      t0, 0x40800000
    fmv.w.x f10, t0
    fsqrt.s f11, f10
    fmv.x.w a0, f11

    # Test 2: sqrt(9.0) = 3.0
    li      t0, 0x41100000
    fmv.w.x f12, t0
    fsqrt.s f13, f12
    fmv.x.w a1, f13

    # Success marker
    li      t3, 0xdeadbeef
    j       _start
EOF

# Compile and run
cd tests/asm
riscv64-unknown-elf-as -march=rv32imaf -mabi=ilp32f -o test_fsqrt_simple.o test_fsqrt_simple.s
riscv64-unknown-elf-ld -m elf32lriscv -Ttext=0x80000000 -o test_fsqrt_simple.elf test_fsqrt_simple.o
riscv64-unknown-elf-objcopy -O binary test_fsqrt_simple.elf test_fsqrt_simple.bin
od -An -tx1 -w1 -v test_fsqrt_simple.bin > test_fsqrt_simple.hex

# Run official tests
cd /home/lei/rv1
env XLEN=32 ./tools/run_official_tests.sh uf
```

---

## Lessons Learned

1. **Parameter naming matters**: `SQRT_CYCLES` suggested one algorithm but implementation used another
2. **Counter initialization is critical**: Off-by-one errors cause silent failures
3. **Debug early**: Adding trace output immediately revealed the skip
4. **Check for multiple assignments**: Counter was initialized in two places, creating a loop
5. **Test incrementally**: Fixing one bug revealed the next (Bug #40)

---

## Next Steps

See `BUG_40_FSQRT_PRECISION.md` for the remaining precision issue and recommended solutions.

---

**🤖 Generated with [Claude Code](https://claude.com/claude-code)**

**Co-Authored-By**: Claude <noreply@anthropic.com>
