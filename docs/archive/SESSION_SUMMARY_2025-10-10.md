# Session Summary - October 10, 2025 (Session 4)

## Session Goal
Debug data forwarding issues in the pipelined core to improve RISC-V compliance test pass rate.

## Starting Status
- **Pass Rate**: 24/42 (57%)
- **Issue**: R-type logical operations (AND, OR, XOR) and right shifts failing
- **Hypothesis**: Data forwarding not eliminating RAW hazards correctly

## Key Discoveries

### 1. **Critical Bug Found: LUI Instruction Using Wrong Operand** ⭐

**Problem**: LUI was using `rs1` as operand A instead of 0!
- U-type instructions don't have rs1 field - bits [19:15] are part of immediate
- Our decoder was extracting "rs1" from those bits (garbage value)
- LUI was computing `rs1 + immediate` instead of `0 + immediate`

**Example**:
```
Instruction: lui x2, 0xf0f0f (0xf0f0f137)
Decoded "rs1": 0x01 (actually part of immediate!)
Computed: x1 + 0xf0f0f000 instead of 0 + 0xf0f0f000
Result: Corrupted register values in loops
```

**Fix Applied**:
```verilog
// rv32i_core_pipelined.v (line 346-348)
assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc :     // AUIPC
                          (idex_opcode == 7'b0110111) ? 32'h0 :        // LUI
                          idex_rs1_data;                                // Others

// rv32i_core.v (line 163-165) - same fix for single-cycle
```

**Impact**:
- Fixed LUI behavior in both single-cycle and pipelined cores
- Pass rate improved: 24/42 → **25/42 (59%)**
- Tests now passing: `srl`, `srli`
- Test 19 patterns now work correctly

### 2. **Additional Enhancement: Register File Internal Forwarding**

Added internal forwarding to register file to handle same-cycle read-write:
```verilog
// register_file.v (lines 41-46)
assign rs1_data = (rs1_addr == 5'h0) ? 32'h0 :
                  (rd_wen && (rd_addr == rs1_addr) && (rd_addr != 5'h0)) ? rd_data :
                  registers[rs1_addr];
```

This creates a 4th level of forwarding: WB-to-ID internal bypass.

## New Issue Discovered: "1 NOP Anomaly" 🔍

### Symptoms
When testing LUI followed by ADDI with different NOP spacing:
- **0 NOPs**: ✅ Works (x2 = 0xff00ff00)
- **1 NOP**: ❌ Corrupted (x3 = 0xfe01ff00, should be 0xff010000)
- **2 NOPs**: ✅ Works (x6 = 0xff00ff00)
- **3 NOPs**: ✅ Works (x8 = 0xff00ff00)

### Impact
- R-type logical ops (AND, OR, XOR) still failing at test #21
- Pattern in test #21 includes specific NOP placements that trigger this bug

### Test Case
Created `tests/asm/test_lui_spacing.s` that reliably reproduces the issue.

## Test Results Summary

### Compliance Tests: 25/42 PASSED (59%)

**✅ Passing Categories (25 tests)**:
- Arithmetic: add, addi, sub (3)
- Logical immediate: andi, ori, xori (3)
- Shifts: sll, slli, srl, srli (4) ← **srl, srli newly fixed**
- Comparisons: slt, slti, sltiu, sltu (4)
- Branches: beq, bne, blt, bge, bltu, bgeu (6)
- Jumps: jal, jalr (2)
- Upper immediate: lui, auipc (2)
- Miscellaneous: simple (1)

**❌ Still Failing (17 tests)**:
1. **R-type Logical** (3): and, or, xor - fail at test #21 (was #19)
2. **Arithmetic Shift** (2): sra, srai - fail at test #25 (was #27)
3. **Loads** (5): lb, lbu, lh, lhu, lw - fail at test #5
4. **Stores** (4): sb, sh, sw - fail at test #7-37
5. **Special** (3): fence_i, ma_data, ld_st, st_ld

### Custom Tests
All basic tests still pass (7/7):
- simple_add, fibonacci, logic_ops, load_store
- shift_ops, branch_test, jump_test

## Files Modified

### RTL Changes
1. **rtl/core/rv32i_core_pipelined.v**
   - Lines 346-348: Fixed LUI operand A selection (use 0 instead of rs1)

2. **rtl/core/rv32i_core.v**
   - Lines 163-165: Fixed LUI operand A selection (single-cycle core)

3. **rtl/core/register_file.v**
   - Lines 41-46: Added internal forwarding for same-cycle read-write

### New Test Cases Created
1. `tests/asm/test_forwarding_and.s` - Minimal RAW hazard test
2. `tests/asm/test_and_loop.s` - Replicate compliance test #19 pattern
3. `tests/asm/test_lui_addi.s` - Simple LUI+ADDI test
4. `tests/asm/test_branch_forward.s` - Forwarding after branch
5. `tests/asm/test_21_pattern.s` - Replicate compliance test #21 pattern
6. `tests/asm/test_lui_spacing.s` - **Reproduces 1-NOP bug** ⭐

## Root Cause Analysis

### Why LUI Bug Went Undetected Initially
1. Simple tests (Phase 1) had natural instruction spacing - no tight LUI+ADDI sequences
2. Compliance tests use compact loops with back-to-back LUI+ADDI
3. The corrupted value looked like a data hazard, masking the real issue

### Why Test #19 Passed But #21 Failed
- Test #19: NOP after both LUI+ADDI pairs → doesn't trigger 1-NOP bug
- Test #21: NOP only between first and second pair → triggers 1-NOP bug

## Next Session Priorities

### 🔥 Priority 1: Debug "1 NOP Anomaly"
**Goal**: Understand why exactly 1 NOP between LUI and dependent instruction causes corruption

**Approach**:
1. Generate waveform for `test_lui_spacing.s`
2. Trace cycle-by-cycle pipeline state for 1-NOP case
3. Check forwarding signals, pipeline register values
4. Compare with 0-NOP (working) and 2-NOP (working) cases
5. Hypothesis: Forwarding unit may be incorrectly handling NOP instructions

**Expected Outcome**: Fix should resolve remaining logical ops failures (+3 tests)

### Priority 2: Debug Arithmetic Right Shifts (sra, srai)
Still failing at test #25 - likely similar forwarding issue

**Expected Gain**: +2 tests

### Priority 3: Debug Load/Store Instructions
All loads fail at test #5, stores fail at various tests
- May be load-use hazard detection issue
- Or forwarding issue with memory operations

**Expected Gain**: +8-9 tests

### Target: 36+/42 (85%+) Pass Rate

## Technical Insights

### Pipeline Forwarding Architecture
Current implementation has 4 levels:
1. **EX-to-EX**: Forward from EX/MEM to EX stage (1 cycle back)
2. **MEM-to-EX**: Forward from MEM/WB to EX stage (2 cycles back)
3. **WB-to-ID**: Forward from WB to ID stage (3 cycles back)
4. **Register File Internal**: Same-cycle write-to-read forwarding

### LUI Instruction Handling
Correct implementation requirements:
- Operand A must be 0 (not rs1)
- Operand B is immediate (upper 20 bits shifted left 12)
- ALU operation: ADD (0 + immediate)
- Result goes to register file via normal WB path

## Statistics
- **Session Duration**: ~4 hours
- **Tests Created**: 6 new test cases
- **Bugs Found**: 2 (1 fixed, 1 discovered)
- **Pass Rate**: 57% → 59% (+2 percentage points)
- **Files Modified**: 3 RTL files
- **Lines Changed**: ~15 lines

## Lessons Learned
1. **U-type instructions don't have rs1** - bits [19:15] are part of immediate
2. **Test incrementally** - spacing tests revealed subtle timing issues
3. **Pipeline timing is subtle** - same code works with 0, 2, 3 NOPs but fails with 1 NOP
4. **Compliance tests are excellent** - they find corner cases simple tests miss

## Current Git Status
Branch: main
Ready to commit changes with comprehensive documentation.

---

**Next Session Goal**: Solve the "1 NOP anomaly" and push pass rate above 85%! 🚀
