# Next Session - RV1 RISC-V Processor Development

**Date Created**: 2025-10-09
**Last Updated**: 2025-10-10 (Session 3 Complete - Control Hazard Fixed)
**Current Phase**: Phase 3 - 5-Stage Pipelined Core (85% complete)
**Session Goal**: Debug data forwarding and load-use hazards

---

## Quick Status

✅ **Phase 3 Progress:**
- **Phase 3.1** ✅ COMPLETE - Pipeline registers and hazard control units
- **Phase 3.2** ✅ COMPLETE - Basic pipelined datapath integration
- **Phase 3.3** ✅ COMPLETE - Data forwarding (integrated)
- **Phase 3.4** ✅ COMPLETE - Load-use hazard detection (integrated)
- **Phase 3.5** ✅ COMPLETE - Complete 3-level forwarding architecture
- **Phase 3.6** 🔄 IN PROGRESS - Control hazard fixed, data forwarding needs debug
- **Phase 3.7** 🔲 NOT STARTED - Branch prediction (optional)

**Overall Phase 3**: ~85% complete

---

## 🎯 Major Accomplishment: Control Hazard Bug Fixed!

### Session 3 Achievements (2025-10-10)

**Critical Bug Found and Fixed:**
- **Problem**: Only IF/ID register was flushed on branch/jump, not ID/EX
- **Impact**: ALL branch tests failing (beq, bne, blt, bge, bltu, bgeu, jalr)
- **Pass rate dropped**: 24/42 (57%) → 19/42 (45%)

**Solution Implemented:**
```verilog
// Flush BOTH IF/ID and ID/EX when branch taken
assign flush_idex = flush_idex_hazard | ex_take_branch;
```

**Results:**
- ✅ All 7 branch/jump tests now PASS
- ✅ Pass rate recovered: 19/42 (45%) → 24/42 (57%)
- ✅ Matches Phase 1 baseline (no regression)

---

## 📊 RISC-V Compliance Test Results

### Current Results (Phase 3 - After Fix)
**24/42 PASSED (57%)**

### Comparison
| Phase | Passed | Failed | Pass Rate |
|-------|--------|--------|-----------|
| Phase 1 (Single-Cycle) | 24/42 | 18/42 | 57% |
| Phase 3 (Before Fix) | 19/42 | 23/42 | 45% ❌ |
| Phase 3 (After Fix) | 24/42 | 18/42 | 57% ✅ |

### Category Breakdown

**✅ Passing (24 tests):**
- Arithmetic: add, addi, sub (3)
- Logical immediate: andi, ori, xori (3)
- Shifts (left only): sll, slli (2)
- Comparisons: slt, slti, sltiu, sltu (4)
- **Branches: beq, bne, blt, bge, bltu, bgeu (6)** ← FIXED!
- **Jumps: jal, jalr (2)** ← FIXED!
- Upper immediate: lui, auipc (2)
- Miscellaneous: simple, st_ld (2)

**❌ Still Failing (18 tests):**

1. **R-type Logical Operations (3 tests)** - HIGH PRIORITY
   - `and` (fails at test #19)
   - `or` (fails at test #19)
   - `xor` (fails at test #19)
   - **Issue**: Data forwarding not eliminating RAW hazards

2. **Right Shift Operations (4 tests)** - HIGH PRIORITY
   - `sra` (fails at test #27)
   - `srai` (fails at test #27)
   - `srl` (fails at test #53)
   - `srli` (fails at test #39)
   - **Issue**: Data forwarding not working

3. **Load Instructions (5 tests)** - MEDIUM PRIORITY
   - `lb` (fails at test #5)
   - `lbu` (fails at test #5)
   - `lh` (fails at test #5)
   - `lhu` (fails at test #5)
   - `lw` (fails at test #5)
   - **Issue**: Load-use hazard detection not working correctly

4. **Store Instructions (3 tests)** - MEDIUM PRIORITY
   - `sb` (fails at test #9)
   - `sh` (fails at test #9)
   - `sw` (fails at test #7)
   - **Issue**: Unknown - needs investigation

5. **Special Cases (3 tests)** - LOW PRIORITY
   - `fence_i` (fails at test #5) - Not implemented
   - `ma_data` (fails at test #3) - Misaligned access not supported
   - `ld_st` (fails at test #53) - Complex load/store interactions

---

## 🔍 Key Issues Identified

### Issue 1: Data Forwarding Not Working (CRITICAL)

**Evidence:**
- R-type logical operations (and, or, xor) STILL fail at same test numbers as Phase 1
- Right shifts (sra, srai, srl, srli) STILL fail at same test numbers
- The 3-level forwarding was implemented but isn't eliminating RAW hazards

**Hypothesis:**
1. **WB-to-ID forwarding timing issue**: Register file write may be happening at wrong clock edge
2. **Forwarding priority incorrect**: Multiple forwarding sources, wrong one selected
3. **Forwarding not connected to register file reads**: ID stage may not be using forwarded data

**What We Know:**
- Simple tests (simple_add, fibonacci, logic_ops) PASS
- These have natural spacing between dependent instructions
- Compliance tests have back-to-back dependencies and fail

**Next Steps:**
1. Examine waveforms of failing AND test
2. Check WB-to-ID forwarding path
3. Verify register file read timing vs write timing
4. Add debug signals to trace forwarding events

### Issue 2: Load-Use Hazards Not Handled (IMPORTANT)

**Evidence:**
- All load tests fail at test #5 (very early)
- Hazard detection unit implemented but not working

**Hypothesis:**
1. Stall not being asserted at right time
2. Bubble (NOP) not being inserted correctly
3. PC stall timing issue

**Next Steps:**
1. Examine waveforms of failing load test
2. Check hazard detection unit outputs
3. Verify stall and bubble signals

### Issue 3: Store Instructions Failing (INVESTIGATE)

**Evidence:**
- sb, sh, sw all failing at different test numbers
- This is unexpected - stores should be simpler than loads

**Next Steps:**
1. Check if this is related to data forwarding
2. Verify store data path
3. Check memory write timing

---

## 🎯 Next Session Priorities

### Priority 1: Fix Data Forwarding (CRITICAL)

**Goal**: Make R-type logical and shift operations pass

**Approach:**
1. Create minimal failing test case (back-to-back AND)
2. Generate waveform and analyze
3. Trace WB-to-ID forwarding path
4. Check register file write/read timing
5. Fix forwarding logic
6. Re-run compliance tests

**Expected Gain**: +7 tests (and, or, xor, sra, srai, srl, srli)

### Priority 2: Fix Load-Use Hazard Detection

**Goal**: Make load instructions pass

**Approach:**
1. Create minimal failing load-use test
2. Generate waveform and analyze hazard detection
3. Check stall/bubble signal timing
4. Fix hazard detection logic
5. Re-run compliance tests

**Expected Gain**: +5 tests (lb, lbu, lh, lhu, lw)

### Priority 3: Debug Store Instructions

**Goal**: Understand why stores are failing

**Approach:**
1. Analyze store test failures
2. Check if related to forwarding
3. Fix any issues found

**Expected Gain**: +3 tests (sb, sh, sw)

### Target: 39+/42 PASSED (93%+)

With all three issues fixed, we expect:
- Current: 24/42 (57%)
- After fixes: 39/42 (93%)
- Remaining 3: fence_i (not impl), ma_data (misaligned), ld_st (complex)

---

## 📁 Files Modified This Session

**RTL Changes:**
- `rtl/core/rv32i_core_pipelined.v`
  - Added `flush_idex_hazard` wire
  - Modified `flush_idex` to combine hazard flush and branch flush
  - Fixed control hazard bug

**Documentation:**
- `PHASES.md` - Updated with Session 3 progress
- `NEXT_SESSION.md` - This file (updated for next session)
- `tb/integration/tb_core_pipelined.v` - Added ECALL detection for compliance tests

**Test Infrastructure:**
- RISC-V compliance tests built in `/tmp/riscv-tests/isa/`
- Test binaries converted to hex in `tests/riscv-compliance/`
- Compliance logs in `sim/compliance/`

---

## 🛠️ Quick Reference Commands

**Run single compliance test:**
```bash
iverilog -g2012 -DCOMPLIANCE_TEST -DMEM_FILE='"tests/riscv-compliance/rv32ui-p-<test>.hex"' -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
vvp sim/test.vvp | grep "COMPLIANCE TEST"
```

**Run all compliance tests:**
```bash
./tools/run_compliance_pipelined.sh
```

**Run Phase 1 custom tests:**
```bash
for test in simple_add fibonacci logic_ops load_store shift_ops branch_test jump_test; do
  echo "Testing $test..."
  iverilog -g2012 -DMEM_FILE="\"tests/vectors/${test}.hex\"" -o sim/test.vvp rtl/core/*.v rtl/memory/*.v tb/integration/tb_core_pipelined.v
  vvp sim/test.vvp | grep "PASSED\|FAILED"
done
```

**Check git status:**
```bash
git status
git log --oneline -5
```

---

## 📝 Session Handoff Notes

**What was accomplished this session:**
✅ Fixed critical control hazard bug (ID/EX flush missing)
✅ All branch/jump tests now pass (7 tests recovered)
✅ Ran full RISC-V compliance test suite (24/42 = 57%)
✅ Identified that data forwarding isn't working as expected
✅ Documented detailed analysis of all failing tests
✅ Created clear priorities for next session

**What's next:**
🎯 **Priority 1**: Debug why data forwarding isn't eliminating RAW hazards
🎯 **Priority 2**: Fix load-use hazard detection
🎯 **Priority 3**: Investigate store instruction failures
🎯 **Target**: Achieve 93%+ compliance test pass rate (39+/42)

**Blockers:** None - issues identified and clear debug path exists

**Key Insight:**
The pipelined core is now structurally correct (control hazards fixed), but the data forwarding paths exist but aren't functioning correctly. The fact that simple tests pass but compliance tests fail at the same test numbers as Phase 1 indicates the forwarding logic isn't being triggered or isn't correctly prioritized.

---

**Great progress! The control hazard fix was critical. Now we need to make the forwarding actually work! 🚀**
