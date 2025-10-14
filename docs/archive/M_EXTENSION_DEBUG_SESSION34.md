# M Extension Debug Session 34

**Date**: 2025-10-12
**Session**: 34
**Status**: 🔶 **IN PROGRESS** - Root cause identified, algorithm fix in progress

---

## Session Goals

Continue debugging the M extension division bugs identified in Session 33.

---

## What We Discovered ✅

### The Real Problem

**Session 33's diagnosis was WRONG!** The issue is NOT with operand forwarding or pipeline data hazards.

**The actual problem**: The division algorithm itself is buggy and produces incorrect results.

### Test Failure Analysis

**Original Report**: "Test #9 fails: `1 ÷ 0 = 0xFFFFFFFF` (div-by-zero)"
**Reality**: Test #4 fails first, at PC 0x800001D4, then branches to fail routine which sets gp=9

**Test 4 Details**:
```assembly
li a1, 20          # 0x14
li a2, -6          # 0xFFFFFFFA (4,294,967,290 unsigned)
divu a4, a1, a2    # Unsigned division: 20 ÷ 4,294,967,290
# Expected: quotient = 0, remainder = 20
# Actual: quotient = 0xFFFFFFF4 (-12 signed)
```

**Why test shows gp=9**: When test 4 fails, it branches to `fail:` routine which:
1. Performs fence
2. Shifts gp left and ORs with 1
3. Calls ECALL with gp value in a0

The fail routine manipulates gp during execution, which is why the final value is 9 instead of 4.

### Division Hardware Investigation

Added comprehensive debug output to trace:
- ✅ ALU results through pipeline stages
- ✅ EX/MEM register transfers
- ✅ MEM/WB register transfers
- ✅ Register file writes in WB stage
- ✅ Division algorithm step-by-step execution

**Findings**:
1. **Operands are correct**: Division unit receives correct values (0x14, 0xFFFFFFFA)
2. **Operation is correct**: DIVU (unsigned) operation code is correct
3. **Forwarding works**: Pipeline forwarding delivers the right values
4. **Algorithm is broken**: The non-restoring division algorithm produces wrong results

---

## Algorithm Problems Identified

### Non-Restoring Division Issues

The original implementation had several bugs:

1. **Sign Extension Error** (Line 203):
   ```verilog
   remainder <= {1'b0, new_A};  // WRONG: Always zero-extends
   ```
   Should have been:
   ```verilog
   remainder <= {new_A[XLEN-1], new_A};  // Sign-extend for non-restoring
   ```

2. **Wrong Sign Bit Check** (Line 194):
   ```verilog
   if (remainder[XLEN-1]) begin  // WRONG: Checks bit 31 of 33-bit value
   ```
   Should check bit 32 (the actual sign bit of the 33-bit remainder).

3. **Incorrect Shift Operation** (Line 188):
   ```verilog
   shifted_A = {remainder[XLEN-2:0], quotient[XLEN-1]};  // WRONG: Missing bit 31
   ```
   Should read `remainder[XLEN-1:0]` to get all 32 bits.

4. **Complex Correction Logic**: Non-restoring requires quotient correction when final remainder is negative, which adds complexity and is error-prone.

### Manual Algorithm Verification

Simulated the non-restoring algorithm in Python for test 4 (20 ÷ 0xFFFFFFFA):
- Algorithm produces: `quotient=0xFFFFFFF4`, `remainder=0xFFFFFFD2` (negative)
- After correction: `quotient=0xFFFFFFF3`, `remainder=0xFFFFFFCC`
- Expected: `quotient=0x00000000`, `remainder=0x00000014`

**Conclusion**: Non-restoring division is fundamentally not working for cases where dividend << divisor in unsigned division.

---

## Attempted Fixes

### Attempt 1: Fix Sign Extension (FAILED)
- Changed remainder update to sign-extend
- Result: Still incorrect (0xFFFFFFF3 instead of 0)

### Attempt 2: Fix Sign Bit Checks (FAILED)
- Changed sign bit check from bit 31 to bit 32
- Result: Correction is applied, but still wrong answer

### Attempt 3: Fix Shift Operation (FAILED)
- Changed shift to read correct bits from remainder
- Result: No improvement

### Attempt 4: Switch to Restoring Division (PARTIAL)

Replaced non-restoring with simpler restoring division algorithm:

**Restoring Division** is simpler:
```
For each bit from MSB to LSB:
  1. Shift {remainder, quotient} left by 1
  2. Trial subtraction: remainder = remainder - divisor
  3. If remainder >= 0: Keep result, set quotient bit to 1
  4. If remainder < 0: Restore (remainder += divisor), set quotient bit to 0
```

**Initial Implementation**:
```verilog
// Initialize
quotient <= {XLEN{1'b0}};           // Start at 0
remainder <= {{1'b0}, abs_dividend}; // Dividend in remainder

// Each cycle
shifted_A = {remainder[XLEN-1:0], quotient[XLEN-1]};
new_A = shifted_A[XLEN-1:0] - divisor_reg;

if (new_A[XLEN-1] == 1'b0) begin  // Non-negative
  q_bit = 1'b1;
  remainder <= {1'b0, new_A};
end else begin  // Negative, restore
  q_bit = 1'b0;
  remainder <= shifted_A;
end
```

**Status**: Implementation has bugs:
- Test 2 (20÷6) now fails: gives 0xFFFFFFE3 instead of 3
- Quotient accumulation is incorrect
- Shift operation may still be wrong

---

## Current Status

**M Extension Test Results**: 50% (4/8 tests passing)
- ✅ MUL: All 5 tests passing
- ❌ DIV: 0/1 tests passing
- ❌ DIVU: 0/1 tests passing
- ❌ REM: 0/1 tests passing
- ❌ REMU: 0/1 tests passing

**Modified Files**:
```
rtl/core/div_unit.v                    # Attempted fixes (now in broken state)
rtl/core/rv32i_core_pipelined.v        # Added debug output
rtl/core/forwarding_unit.v             # Added debug output (from Session 33)
rtl/core/idex_register.v               # Added debug output (from Session 33)
tools/debug_m_division.sh              # Enhanced debug script
```

---

## Options for Next Session

### **Option 1: Use Reference Implementation (RECOMMENDED)** 🎯

**Approach**: Find a proven RISC-V division implementation and adapt it

**Candidate Sources**:
1. **VexRiscv** - FPGA-friendly RISC-V core with iterative division
   - GitHub: SpinalHDL/VexRiscv
   - Known to work correctly
   - Uses M extension with 32/divUnrollFactor + 1 cycles

2. **PicoRV32** - Simple, well-tested RISC-V implementation
   - GitHub: cliffordwolf/picorv32
   - Clear, readable code
   - Proven in many FPGA designs

3. **Rocket Chip** - UC Berkeley's RISC-V implementation
   - More complex but very well verified
   - Industry-standard reference

**Steps**:
1. Clone reference implementation
2. Extract division unit code
3. Adapt to our interface (input/output ports, state machine)
4. Test with our testbench
5. Verify compliance

**Estimated Time**: 2-3 hours

**Pros**:
- ✅ Proven to work
- ✅ Fast path to working solution
- ✅ Learn from expert implementations
- ✅ Less debugging time

**Cons**:
- ⚠️ May need license compatibility check
- ⚠️ Code style may differ from our project
- ⚠️ Need to understand their algorithm

---

### **Option 2: Simple Sequential Subtraction**

**Approach**: Use dead-simple algorithm: quotient = 0; while (dividend >= divisor) { dividend -= divisor; quotient++; }

**Algorithm**:
```verilog
// State machine:
// IDLE -> LOOP -> DONE

LOOP:
  if (remainder >= divisor) begin
    remainder <= remainder - divisor;
    quotient <= quotient + 1;
    // Stay in LOOP
  end else begin
    // Done: quotient = quotient, remainder = remainder
    state <= DONE;
  end
```

**Steps**:
1. Implement simple loop-based division
2. Handle signed operations separately (convert to unsigned, do division, fix signs)
3. Test and verify
4. Optimize later if needed (radix-2, radix-4, etc.)

**Estimated Time**: 1-2 hours

**Pros**:
- ✅ Trivially correct algorithm
- ✅ Easy to understand and verify
- ✅ No bit manipulation tricks
- ✅ Can optimize later

**Cons**:
- ❌ Very slow (worst case: O(2^32) cycles for 32-bit)
- ❌ Not practical for real use
- ❌ Would need optimization anyway

---

### **Option 3: Debug Current Restoring Division**

**Approach**: Continue fixing the restoring division implementation

**Steps**:
1. Find a reference description of restoring division algorithm
2. Manually trace through 20÷6 step-by-step on paper
3. Compare with Verilog implementation
4. Fix the discrepancies
5. Test incrementally

**Estimated Time**: 3-5 hours (uncertain)

**Pros**:
- ✅ Finish what we started
- ✅ Learn algorithm deeply
- ✅ Full control over implementation

**Cons**:
- ❌ Already spent 4 hours debugging
- ❌ Multiple attempts failed
- ❌ Algorithm is tricky to get right
- ❌ No guarantee we'll find all bugs

---

## Recommendation

**Choose Option 1: Use Reference Implementation**

**Rationale**:
1. We've already spent significant time (Sessions 32, 33, 34) debugging division
2. The algorithm bugs are subtle and time-consuming to fix
3. Using proven code ensures correctness
4. We can learn from expert implementations
5. Fastest path to 100% M extension compliance

**Suggested Workflow for Next Session**:
```bash
# 1. Clone VexRiscv or PicoRV32
cd /tmp
git clone https://github.com/SpinalHDL/VexRiscv.git
# or
git clone https://github.com/cliffordwolf/picorv32.git

# 2. Find their division unit
# VexRiscv: Look for MulDiv plugin
# PicoRV32: Look for div instructions in picorv32.v

# 3. Study the algorithm
# Read the code, understand the state machine

# 4. Adapt to our interface
# Copy the algorithm, adjust to our ports and parameters

# 5. Test
./tools/run_official_tests.sh m
```

---

## Key Insights

1. **Non-restoring division is tricky**: Signed arithmetic, careful bit manipulation, complex correction
2. **Restoring division is simpler**: But still requires correct initialization and shifting
3. **Testing is critical**: Small bugs in division produce wildly wrong results
4. **Reference implementations exist**: No need to reinvent the wheel

---

## Debug Infrastructure Created

The debug infrastructure we built is valuable for future work:

**New Debug Flags**:
- `DEBUG_ALU`: Traces ALU results
- `DEBUG_EXMEM`: Traces EX→MEM pipeline transfer
- `DEBUG_MEMWB`: Traces MEM→WB pipeline transfer
- `DEBUG_REGFILE_WB`: Traces register file writes
- `DEBUG_DIV_STEPS`: Traces division algorithm step-by-step

**Enhanced Debug Script**: `tools/debug_m_division.sh`
- Compiles with all debug flags
- Runs DIVU test
- Saves detailed log

**Usage**:
```bash
./tools/debug_m_division.sh
grep "\[DIV" debug_m_division.log  # See division steps
```

---

## Files Modified in This Session

```
rtl/core/div_unit.v                    # Major changes (multiple algorithm attempts)
rtl/core/rv32i_core_pipelined.v        # Added debug output for ALU/pipeline
tools/debug_m_division.sh              # Enhanced with new debug flags
M_EXTENSION_DEBUG_SESSION34.md         # This document
```

---

## Next Session Quick Start

```bash
cd /home/lei/rv1

# Review this document
cat M_EXTENSION_DEBUG_SESSION34.md

# Check git status
git status
git diff rtl/core/div_unit.v  # See all the attempted fixes

# Option 1 (Recommended): Clone reference implementation
cd /tmp
git clone https://github.com/SpinalHDL/VexRiscv.git
# Study their MulDiv unit

# Or Option 2: Simple algorithm
# Edit rtl/core/div_unit.v with simple loop-based division

# Or Option 3: Continue debugging
./tools/debug_m_division.sh
# Analyze debug_m_division.log carefully
```

---

## Current Test Status Summary

| Extension | Tests | Passing | Status |
|-----------|-------|---------|--------|
| **I** | 42 | 42 | ✅ 100% |
| **M** | 8 | 4 | 🔶 50% |
| MUL | 5 | 5 | ✅ 100% |
| DIV | 1 | 0 | ❌ 0% |
| DIVU | 1 | 0 | ❌ 0% |
| REM | 1 | 0 | ❌ 0% |
| REMU | 1 | 0 | ❌ 0% |
| **A** | ? | ? | ⚪ Not tested |
| **C** | ? | ? | ⚪ Not tested |
| **F** | ? | ? | ⚪ Not tested |
| **D** | ? | ? | ⚪ Not tested |

---

## Conclusion

Session 34 successfully identified the root cause: **the division algorithm itself is buggy**, not the pipeline forwarding. We attempted multiple fixes but the algorithm remains broken.

**For next session**: Use a proven reference implementation (Option 1) to quickly get working division and achieve 100% M extension compliance.

**Estimated remaining work**: 2-3 hours to adapt reference code and verify

---

**Ready for Session 35!** 🚀

Choose Option 1 and let's get those division tests passing! 💪
