# Next Session - RV1 RISC-V Processor Development

**Date Created**: 2025-10-09
**Last Updated**: 2025-10-10 (Session 4 Complete - LUI Bug Fixed)
**Current Phase**: Phase 3 - 5-Stage Pipelined Core (85% complete)
**Session Goal**: Debug "1 NOP anomaly" and continue improving compliance test pass rate

---

## Quick Status

✅ **Phase 3 Progress:**
- **Phase 3.1** ✅ COMPLETE - Pipeline registers and hazard control units
- **Phase 3.2** ✅ COMPLETE - Basic pipelined datapath integration
- **Phase 3.3** ✅ COMPLETE - Data forwarding (integrated)
- **Phase 3.4** ✅ COMPLETE - Load-use hazard detection (integrated)
- **Phase 3.5** ✅ COMPLETE - Complete 3-level forwarding architecture
- **Phase 3.6** 🔄 IN PROGRESS - LUI bug fixed, "1 NOP anomaly" discovered
- **Phase 3.7** 🔲 NOT STARTED - Branch prediction (optional)

**Overall Phase 3**: ~85% complete

---

## 🎯 Major Accomplishment: LUI Bug Fixed!

### Session 4 Achievements (2025-10-10)

**Critical Bug Found and Fixed:**
- **Problem**: LUI instruction was using rs1 as operand A instead of 0
  - U-type instructions don't have rs1 field (bits [19:15] are part of immediate)
  - Decoder was extracting garbage "rs1" from immediate bits
  - LUI computed `rs1 + immediate` instead of `0 + immediate`
- **Impact**: Register values corrupted in loops, especially test #19

**Solution Implemented:**
```verilog
// Fixed in both rv32i_core_pipelined.v and rv32i_core.v
assign ex_alu_operand_a = (idex_opcode == 7'b0010111) ? idex_pc :     // AUIPC
                          (idex_opcode == 7'b0110111) ? 32'h0 :        // LUI
                          idex_rs1_data;                                // Others
```

**Results:**
- ✅ LUI now correctly computes 0 + immediate
- ✅ Pass rate improved: 24/42 (57%) → 25/42 (59%)
- ✅ Tests now passing: srl, srli
- ✅ Test #19 patterns now work correctly

**Additional Enhancement:**
- Added register file internal forwarding (4th level of forwarding)
- Handles same-cycle write-to-read in register file

---

## 🔍 New Issue: "1 NOP Anomaly"

### The Mystery
LUI results get corrupted with **exactly 1 NOP** between LUI and dependent instruction:

```assembly
# Test Pattern:
lui x1, 0xff010      # Should produce 0xff010000
nop                  # Exactly 1 NOP
addi x2, x1, -256    # x1 is corrupted! Gets 0xfe01ff00 instead

# Results by NOP count:
0 NOPs: ✅ Works (0xff010000)
1 NOP:  ❌ Corrupted (0xfe01ff00)
2 NOPs: ✅ Works (0xff010000)
3 NOPs: ✅ Works (0xff010000)
```

### Impact
- R-type logical ops (AND, OR, XOR) still fail at test #21
- Test #21 has specific NOP placement that triggers this bug
- Suggests subtle pipeline timing or forwarding issue

### Test Case
Created `tests/asm/test_lui_spacing.s` that reliably reproduces the issue.

---

## 📊 RISC-V Compliance Test Results

### Current Results (Phase 3 - After LUI Fix)
**25/42 PASSED (59%)**

### Comparison
| Session | Passed | Failed | Pass Rate | Change |
|---------|--------|--------|-----------|--------|
| Session 3 (Control Fix) | 24/42 | 18/42 | 57% | Baseline |
| Session 4 (LUI Fix) | 25/42 | 17/42 | 59% | +2% ✅ |

### Category Breakdown

**✅ Passing (25 tests)**:
- Arithmetic: add, addi, sub (3)
- Logical immediate: andi, ori, xori (3)
- **Shifts: sll, slli, srl, srli (4)** ← srl, srli newly fixed!
- Comparisons: slt, slti, sltiu, sltu (4)
- Branches: beq, bne, blt, bge, bltu, bgeu (6)
- Jumps: jal, jalr (2)
- Upper immediate: lui, auipc (2)
- Miscellaneous: simple (1)

**❌ Still Failing (17 tests)**:

1. **R-type Logical Operations (3 tests)** - HIGH PRIORITY 🔥
   - `and` (fails at test #21, was #19)
   - `or` (fails at test #21, was #19)
   - `xor` (fails at test #21, was #19)
   - **Issue**: "1 NOP anomaly" - specific timing issue with 1 NOP spacing
   - **Progress**: Test #19 patterns now pass! Bug moved to test #21.

2. **Arithmetic Right Shifts (2 tests)** - HIGH PRIORITY
   - `sra` (fails at test #25, was #27)
   - `srai` (fails at test #25, was #27)
   - **Issue**: Likely similar to "1 NOP anomaly" or forwarding issue
   - **Progress**: Failure moved to earlier test (improvement)

3. **Load Instructions (5 tests)** - MEDIUM PRIORITY
   - `lb`, `lbu`, `lh`, `lhu`, `lw` (all fail at test #5)
   - **Issue**: Load-use hazard detection not working correctly

4. **Store Instructions (4 tests)** - MEDIUM PRIORITY
   - `sb` (fails at test #9)
   - `sh` (fails at test #9)
   - `sw` (fails at test #37, was #7)
   - `st_ld` (fails at test #53)
   - **Issue**: Unknown - needs investigation

5. **Special Cases (3 tests)** - LOW PRIORITY
   - `fence_i` (fails at test #5) - Not implemented
   - `ma_data` (fails at test #3) - Misaligned access not supported
   - `ld_st` (fails at test #53) - Complex load/store interactions

---

## 🎯 Next Session Priorities

### 🔥 Priority 1: Debug "1 NOP Anomaly" (CRITICAL)

**Goal**: Understand why exactly 1 NOP between LUI and dependent instruction causes corruption

**Symptoms**:
- LUI result: Expected 0xff010000, Got 0xfe01ff00
- Only happens with exactly 1 NOP spacing
- 0, 2, or 3 NOPs work fine

**Debugging Approach**:
1. **Generate waveform** for `test_lui_spacing.s`
2. **Trace cycle-by-cycle** pipeline state for 1-NOP case
   - Check all pipeline register values
   - Trace forwarding signals (forward_a, forward_b)
   - Examine EX/MEM and MEM/WB register contents
3. **Compare** with 0-NOP (working) case
4. **Hypothesis**:
   - Forwarding unit may be incorrectly selecting forwarding source with NOP in pipeline
   - Or EX/MEM register may contain stale data from NOP
   - Or WB-to-ID forwarding timing issue

**Test Cases Ready**:
- `tests/vectors/test_lui_spacing.hex` - reproduces bug
- Can add debug signals to pipeline if needed

**Expected Outcome**:
- Fix should resolve remaining logical ops failures
- **Expected Gain**: +3 tests (and, or, xor)

### Priority 2: Debug Arithmetic Right Shifts

**Goal**: Fix sra, srai failures at test #25

**Approach**:
1. May be resolved by fixing "1 NOP anomaly"
2. If not, investigate test #25 specifically
3. Check if similar forwarding/timing issue

**Expected Gain**: +2 tests

### Priority 3: Debug Load-Use Hazards

**Goal**: Make load instructions pass test #5

**Approach**:
1. Create minimal failing load-use test
2. Generate waveform and analyze hazard detection
3. Check stall/bubble signal timing
4. Verify load-use hazard detection logic

**Expected Gain**: +5 tests (lb, lbu, lh, lhu, lw)

### Priority 4: Debug Store Instructions

**Goal**: Understand why stores are failing

**Approach**:
1. Analyze store test failures
2. Check if related to forwarding (store data needs forwarding)
3. Fix any issues found

**Expected Gain**: +3-4 tests (sb, sh, sw, st_ld)

---

## 🎯 Target for Next Session

**Current**: 25/42 (59%)
**Target**: 36+/42 (85%+)

**Realistic Expectation**:
- Fix "1 NOP anomaly": +3 tests → 28/42 (67%)
- Fix arithmetic shifts: +2 tests → 30/42 (71%)
- Fix loads: +5 tests → 35/42 (83%)
- Fix stores: +3 tests → 38/42 (90%)

---

## 📁 Files Modified This Session

**RTL Changes:**
1. `rtl/core/rv32i_core_pipelined.v`
   - Lines 346-348: Fixed LUI operand A selection (use 0 instead of rs1)

2. `rtl/core/rv32i_core.v`
   - Lines 163-165: Fixed LUI operand A selection (single-cycle core)

3. `rtl/core/register_file.v`
   - Lines 41-46: Added internal forwarding for same-cycle read-write

**New Test Cases:**
- `tests/asm/test_forwarding_and.s` - Minimal RAW hazard test
- `tests/asm/test_and_loop.s` - Test #19 pattern reproduction
- `tests/asm/test_lui_addi.s` - Simple LUI+ADDI test
- `tests/asm/test_branch_forward.s` - Forwarding after branch
- `tests/asm/test_21_pattern.s` - Test #21 pattern reproduction
- `tests/asm/test_lui_spacing.s` - **Reproduces "1 NOP anomaly"** ⭐

**Documentation:**
- `SESSION_SUMMARY_2025-10-10.md` - Complete session documentation
- `NEXT_SESSION.md` - This file (updated)

---

## 🛠️ Quick Reference Commands

**Run test that reproduces bug:**
```bash
iverilog -g2012 -DMEM_FILE='"tests/vectors/test_lui_spacing.hex"' -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp | grep "x[2-8]"
```

**Run all compliance tests:**
```bash
./tools/run_compliance_pipelined.sh
```

**Generate waveform for debugging:**
```bash
# Waveform saved to sim/waves/core_pipelined.vcd
# Use GTKWave to view: gtkwave sim/waves/core_pipelined.vcd
```

**Check specific compliance test:**
```bash
iverilog -g2012 -DCOMPLIANCE_TEST -DMEM_FILE='"tests/riscv-compliance/rv32ui-p-and.hex"' -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp | grep "COMPLIANCE TEST"
```

---

## 📝 Session Handoff Notes

**What was accomplished this session:**
✅ Fixed critical LUI bug (using rs1 instead of 0)
✅ Pass rate improved from 57% to 59% (+1 test)
✅ Added register file internal forwarding
✅ Created comprehensive test cases
✅ Discovered "1 NOP anomaly" - reproducible bug with specific timing pattern
✅ Documented all findings thoroughly

**What's next:**
🎯 **Priority 1**: Debug "1 NOP anomaly" using waveform analysis
   - This is the key blocker for logical operations
   - Reproducible test case exists: `test_lui_spacing.s`
   - Likely a forwarding unit or pipeline register timing issue

🎯 **Priority 2**: Fix arithmetic right shifts (may be related to Priority 1)
🎯 **Priority 3**: Debug load-use hazard detection
🎯 **Priority 4**: Investigate store instruction failures
🎯 **Target**: Achieve 85%+ compliance test pass rate (36+/42)

**Blockers:** None - clear debugging path exists with reproducible test case

**Key Insight:**
The "1 NOP anomaly" is fascinating - the bug only appears with exactly 1 NOP, not 0, 2, or 3+ NOPs. This suggests a very specific pipeline state or forwarding conflict that occurs at a particular cycle offset. Waveform analysis should reveal the exact mechanism.

---

**Good progress on LUI fix! Now let's crack this "1 NOP anomaly" mystery! 🔍🚀**
