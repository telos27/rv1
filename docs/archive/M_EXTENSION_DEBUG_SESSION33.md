# M Extension Division Bug Debug Session

**Date**: 2025-10-12
**Session**: 33
**Status**: Bug root cause identified, fix still in progress

---

## Problem Statement

M extension division-by-zero tests failing (DIVU, REM, REMU):
- **Expected**: `1 / 0 = 0xFFFFFFFF`
- **Actual**: `1 / 0 = 0xFFFFFFF4` (wrong operands: 0x14 / 0xFFFFFFFA)

Test Status: 5/8 passing (62%)

---

## Debug Infrastructure Added

### Files Modified
1. **`rtl/core/forwarding_unit.v`**: Added `DEBUG_FORWARD` output for forwarding decisions
2. **`rtl/core/idex_register.v`**: Added `DEBUG_IDEX` output for pipeline register updates
3. **`rtl/core/rv32i_core_pipelined.v`**: Added `DEBUG_M_OPERANDS` output for operand paths
4. **`tools/debug_m_division.sh`**: Created debug script with all flags enabled

### Debug Findings

From `debug_m_division_full.log` analysis:

**Test 9 Execution** (the failing test):
```assembly
li gp, 9       # Test number
li a1, 1       # a1 should = 1
li a2, 0       # a2 should = 0
divu a4, a1, a2 # a4 = 1 ÷ 0 (expect 0xFFFFFFFF)
```

**Actual Values at DIVU Execution**:
```
[IDEX] HELD: rs1=x11[00000014] rs2=x12[fffffffa] rd=x14 mul_div=1
```
- a1 (x11) = 0x14 = 20 (from test 4: `li a1, 20`)
- a2 (x12) = 0xFFFFFFFA = -6 (from test 5: `li a2, -6`)

**Forwarding Activity**:
```
[FORWARD_A] WB hazard: rs1=x11 matches memwb_rd=x11 (fwd=2'b01)
[FORWARD_B] MEM hazard: rs2=x12 matches exmem_rd=x12 (fwd=2'b10)
[M_OPERANDS] operand_a: idex_rs1_data=00000014 fwd_a=01 wb=00000014 → result=00000014
[M_OPERANDS] operand_b: idex_rs2_data=fffffffa fwd_b=10 exmem=fffffffa → result=fffffffa
```

Forwarding IS happening, but forwarding **STALE** values!

---

## Root Cause Analysis

### What's Working ✅
1. **Division hardware**: Standalone test confirms div_unit is correct
2. **Decoder**: Correctly extracts rs1=x11, rs2=x12, rd=x14
3. **IDEX register**: Holds correctly during M operation
4. **Forwarding detection**: Correctly detects WB/MEM hazards
5. **Pipeline stalling**: M instructions correctly stall IF/ID stages

### What's Broken ❌
1. **Register file has stale values**: a1=0x14, a2=0xFFFFFFFA from previous tests
2. **Forwarding paths have stale values**: WB and MEM stages contain old results
3. **LI instructions don't update registers**: `li a1, 1` and `li a2, 0` execute but values 1 and 0 never appear in register file or forwarding paths

### The Mystery

The LI instructions SHOULD:
1. Enter ID stage, read x0 (always 0) and immediate value
2. Enter EX stage, ALU computes `0 + 1 = 1` (for `li a1, 1`)
3. Enter MEM stage, result `1` is in `exmem_alu_result`
4. Enter WB stage, result `1` is in `memwb_alu_result` and written to register file
5. DIVU in EX stage should forward value `1` from WB

BUT the debug shows:
- DIVU forwards `wb=0x14` not `wb=0x1`
- This means WB stage has OLD data from a previous instruction!

**Hypothesis**: Something is clearing/flushing/overwriting the LI results before they reach WB, OR there's a timing issue where the pipeline state from the previous test's DIVU completion corrupts the next test's initial instructions.

---

## Attempted Fixes

### Fix 1: Latch Operands in div_unit
```verilog
reg [XLEN-1:0] dividend_reg;  // Store original dividend
```
**Result**: No improvement. Operands already wrong when latched.

### Fix 2: Latch Operands in mul_div_unit
```verilog
reg [XLEN-1:0] operand_a_reg, operand_b_reg;
// Latch on start signal
```
**Result**: No improvement. Operands already wrong when first sampled.

### Fix 3: Latch from IDEX (Raw Values)
```verilog
m_operand_a_latched <= idex_rs1_data;
m_operand_b_latched <= idex_rs2_data;
```
**Result**: No improvement. IDEX values are stale (from register file).

### Fix 4: Latch from Forwarded Wires
```verilog
m_operand_a_latched <= ex_alu_operand_a_forwarded;
m_operand_b_latched <= ex_rs2_data_forwarded;
```
**Result**: No improvement. Forwarded values are already stale when M instruction enters EX.

---

## Key Observations

1. **No div-by-zero operations reach div_unit**: Searched entire log for `div_by_zero=1`, found ZERO occurrences. The divisor=0 never makes it to the division hardware.

2. **Pipeline flushes occur**: Two FLUSH events happen right before test 9:
   ```
   [IDEX] FLUSH: inserting NOP bubble
   [IDEX] FLUSH: inserting NOP bubble
   [IDEX] UPDATE: ... rd=x0→x3 mul_div=0→0   ← li gp, 9
   ```
   These might be from branch resolution, but could be relevant.

3. **LI instruction data flow unclear**: Debug doesn't show immediate values or ALU outputs for LI instructions, making it hard to confirm if they compute correct results.

4. **Hazard detection only handles LOADs**: The hazard_detection_unit only creates pipeline stalls for LOAD-USE hazards, not general RAW (read-after-write) hazards. It relies on forwarding for ALU results, but forwarding is providing wrong values!

---

## Recommended Next Steps

###1. Add More Detailed Debug
- Add debug for ALU outputs (`ex_alu_result`)
- Add debug for EX/MEM pipeline register (`exmem_alu_result`)
- Add debug for MEM/WB pipeline register (`memwb_alu_result`)
- Add debug for register file write port (what values are actually written)
- Add debug for immediate values in IDEX

### 2. Trace Specific Values
Follow the value `1` (from `li a1, 1`) through the entire pipeline:
- Where does ALU compute it?
- Does it make it to EX/MEM?
- Does it make it to MEM/WB?
- Does it get written to register file?
- If it gets lost, WHERE and WHY?

### 3. Check Pipeline State Transitions
Examine what happens during test 8 → test 9 transition:
- Test 8's DIVU completes (cycle N)
- Pipeline resumes (cycle N+1)
- What instructions are in each stage?
- Are there any spurious flushes/stalls/holds?

### 4. Consider Structural Fix
If forwarding continues to be unreliable, consider:
- Adding RAW hazard detection for M instructions (stall until sources are in register file)
- Or: Fix whatever is corrupting the pipeline state during/after M operations

---

## Test Status

### Currently Passing (5/8)
- ✅ DIV (signed division)
- ✅ MUL, MULH, MULHSU, MULHU (all multiplication tests)

### Currently Failing (3/8)
- ❌ DIVU (unsigned division) - Test 9 fails (1/0 returns wrong result)
- ❌ REM (signed remainder) - Test 13 fails
- ❌ REMU (unsigned remainder) - Test 9 fails

All failures appear to be the same issue: wrong operands due to stale register/forwarding values.

---

## Files Modified This Session

```
rtl/core/forwarding_unit.v          # Added DEBUG_FORWARD
rtl/core/idex_register.v             # Added DEBUG_IDEX
rtl/core/rv32i_core_pipelined.v      # Added DEBUG_M_OPERANDS + attempted fixes
tools/debug_m_division.sh            # Created debug script
debug_m_division_full.log            # Debug output log (437 lines)
M_EXTENSION_DEBUG_SESSION33.md       # This file
```

---

## Conclusion

The M extension division bug is **not in the division hardware** but rather a **pipeline data hazard issue** where stale register/forwarding values corrupt M instruction operands.

The investigation has narrowed down the problem to the pipeline control and data forwarding logic, specifically how values propagate through EX→MEM→WB stages when M instructions hold the pipeline for extended periods.

Further debugging requires tracing individual data values through the pipeline to identify exactly where/when they get lost or corrupted.

**Status**: Investigation ongoing, root cause identified but fix not yet found.
