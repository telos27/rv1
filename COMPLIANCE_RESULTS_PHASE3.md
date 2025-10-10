# RISC-V Compliance Test Results - Phase 3 Pipelined Core

**Date**: 2025-10-10
**Phase**: Phase 3 - 5-Stage Pipelined Core
**Test Suite**: riscv-tests RV32UI (User-level Integer)
**Core**: rv32i_core_pipelined.v (465 lines)

---

## Summary

- **Total Tests**: 42
- **Passed**: 24 (57%)
- **Failed**: 18 (43%)
- **Target**: 90% (39+/42) - not yet achieved

---

## Comparison with Phase 1

| Phase | Architecture | Passed | Failed | Pass Rate | Status |
|-------|--------------|--------|--------|-----------|--------|
| Phase 1 | Single-Cycle | 24/42 | 18/42 | 57% | Baseline |
| Phase 3 (Initial) | Pipelined | 19/42 | 23/42 | 45% | ❌ Regression |
| Phase 3 (Fixed) | Pipelined | 24/42 | 18/42 | 57% | ✅ Restored |

**Key Takeaway**: After fixing the control hazard bug, the pipelined core matches Phase 1 baseline performance.

---

## Bug Fixed This Session

### Control Hazard Bug (CRITICAL)

**Problem:**
- When a branch/jump was taken in the EX stage, only the IF/ID pipeline register was flushed
- The ID/EX register (containing the instruction after the branch) was NOT flushed
- This caused the "shadow" instruction to execute incorrectly

**Impact:**
- ALL 6 branch tests failed (beq, bne, blt, bge, bltu, bgeu)
- JALR (indirect jump) failed
- Pass rate dropped from 57% to 45%

**Solution:**
```verilog
// Before: Only flushed IF/ID
assign flush_ifid = ex_take_branch;

// After: Flush BOTH IF/ID and ID/EX
assign flush_ifid = ex_take_branch;
assign flush_idex = flush_idex_hazard | ex_take_branch;
```

**Result:**
- All 7 branch/jump tests now PASS
- Pass rate recovered to 57%

---

## Detailed Results

### ✅ Passed Tests (24)

| # | Test Name | Category | Notes |
|---|-----------|----------|-------|
| 1 | rv32ui-p-add | Arithmetic | R-type addition |
| 2 | rv32ui-p-addi | Arithmetic | I-type add immediate |
| 3 | rv32ui-p-andi | Logical Imm | AND immediate |
| 4 | rv32ui-p-auipc | Upper Imm | Add upper immediate to PC |
| 5 | rv32ui-p-beq | Branch | Branch if equal ✅ FIXED |
| 6 | rv32ui-p-bge | Branch | Branch if ≥ (signed) ✅ FIXED |
| 7 | rv32ui-p-bgeu | Branch | Branch if ≥ (unsigned) ✅ FIXED |
| 8 | rv32ui-p-blt | Branch | Branch if < (signed) ✅ FIXED |
| 9 | rv32ui-p-bltu | Branch | Branch if < (unsigned) ✅ FIXED |
| 10 | rv32ui-p-bne | Branch | Branch if not equal ✅ FIXED |
| 11 | rv32ui-p-jal | Jump | Jump and link |
| 12 | rv32ui-p-jalr | Jump | Jump and link register ✅ FIXED |
| 13 | rv32ui-p-lui | Upper Imm | Load upper immediate |
| 14 | rv32ui-p-ori | Logical Imm | OR immediate |
| 15 | rv32ui-p-simple | Basic | Simple test |
| 16 | rv32ui-p-sll | Shift | Shift left logical |
| 17 | rv32ui-p-slli | Shift | Shift left logical immediate |
| 18 | rv32ui-p-slt | Compare | Set less than |
| 19 | rv32ui-p-slti | Compare | Set less than immediate |
| 20 | rv32ui-p-sltiu | Compare | Set less than immediate unsigned |
| 21 | rv32ui-p-sltu | Compare | Set less than unsigned |
| 22 | rv32ui-p-st_ld | Memory | Store/load combined test |
| 23 | rv32ui-p-sub | Arithmetic | R-type subtraction |
| 24 | rv32ui-p-xori | Logical Imm | XOR immediate |

### ❌ Failed Tests (18)

#### Category 1: R-type Logical Operations (3 tests) - HIGH PRIORITY

| Test | Fails At | Status | Issue |
|------|----------|--------|-------|
| rv32ui-p-and | Test #19 | ❌ FAILED | Data forwarding not working |
| rv32ui-p-or | Test #19 | ❌ FAILED | Data forwarding not working |
| rv32ui-p-xor | Test #19 | ❌ FAILED | Data forwarding not working |

**Root Cause**: The 3-level forwarding architecture exists but isn't eliminating RAW hazards. These tests fail at the SAME test numbers as Phase 1, indicating forwarding is not functioning.

**Expected Behavior**: With proper forwarding, back-to-back dependent AND/OR/XOR operations should work without stalls.

#### Category 2: Right Shift Operations (4 tests) - HIGH PRIORITY

| Test | Fails At | Status | Issue |
|------|----------|--------|-------|
| rv32ui-p-sra | Test #27 | ❌ FAILED | Data forwarding not working |
| rv32ui-p-srai | Test #27 | ❌ FAILED | Data forwarding not working |
| rv32ui-p-srl | Test #53 | ❌ FAILED | Data forwarding not working |
| rv32ui-p-srli | Test #39 | ❌ FAILED | Data forwarding not working |

**Root Cause**: Same as R-type logical - data forwarding issue.

**Note**: Left shifts (SLL, SLLI) pass, but right shifts fail. This is the same pattern as Phase 1.

#### Category 3: Load Instructions (5 tests) - MEDIUM PRIORITY

| Test | Fails At | Status | Issue |
|------|----------|--------|-------|
| rv32ui-p-lb | Test #5 | ❌ FAILED | Load-use hazard not detected |
| rv32ui-p-lbu | Test #5 | ❌ FAILED | Load-use hazard not detected |
| rv32ui-p-lh | Test #5 | ❌ FAILED | Load-use hazard not detected |
| rv32ui-p-lhu | Test #5 | ❌ FAILED | Load-use hazard not detected |
| rv32ui-p-lw | Test #5 | ❌ FAILED | Load-use hazard not detected |

**Root Cause**: Load-use hazard detection unit implemented but not working correctly. Tests fail very early (test #5), suggesting the stall/bubble mechanism isn't triggering.

**Expected Behavior**: When a load is followed by an instruction that uses the loaded data, a 1-cycle stall should be inserted.

#### Category 4: Store Instructions (3 tests) - MEDIUM PRIORITY

| Test | Fails At | Status | Issue |
|------|----------|--------|-------|
| rv32ui-p-sb | Test #9 | ❌ FAILED | Unknown - needs investigation |
| rv32ui-p-sh | Test #9 | ❌ FAILED | Unknown - needs investigation |
| rv32ui-p-sw | Test #7 | ❌ FAILED | Unknown - needs investigation |

**Root Cause**: Unknown. Could be related to data forwarding or store data path timing.

**Note**: Store byte and halfword fail at same test (#9), while store word fails earlier (#7).

#### Category 5: Special Cases (3 tests) - LOW PRIORITY

| Test | Fails At | Status | Issue |
|------|----------|--------|-------|
| rv32ui-p-fence_i | Test #5 | ❌ FAILED | FENCE.I not implemented |
| rv32ui-p-ma_data | Test #3 | ❌ FAILED | Misaligned access not supported |
| rv32ui-p-ld_st | Test #53 | ❌ FAILED | Complex load/store interaction |

**Root Cause**: These are expected failures:
- `fence_i`: Instruction fence not implemented (requires I-cache flush)
- `ma_data`: Misaligned data access not supported
- `ld_st`: Complex test with many load/store patterns

---

## Analysis by Category

### Passing Categories ✅
- ✅ **Arithmetic**: ADD, ADDI, SUB all pass
- ✅ **Immediate Logical**: ANDI, ORI, XORI all pass
- ✅ **Left Shifts**: SLL, SLLI pass
- ✅ **Comparisons**: All 4 comparison types pass
- ✅ **Branches**: All 6 branch types pass (FIXED!)
- ✅ **Jumps**: JAL, JALR pass (FIXED!)
- ✅ **Upper Immediate**: LUI, AUIPC pass

### Failing Categories ❌
- ❌ **R-type Logical**: 0/3 passing (AND, OR, XOR)
- ❌ **Right Shifts**: 0/4 passing (SRA, SRAI, SRL, SRLI)
- ❌ **Loads**: 0/5 passing (LB, LBU, LH, LHU, LW)
- ❌ **Stores**: 0/3 passing (SB, SH, SW)
- ❌ **Special**: 0/3 passing (FENCE.I, misaligned, complex)

**Pattern**: The failures are concentrated in:
1. Data forwarding issues (7 tests)
2. Load-use hazard handling (5 tests)
3. Store operations (3 tests)
4. Unimplemented features (3 tests)

---

## Progress Tracking

### Session 1 (2025-10-10 AM)
- Implemented pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB)
- Implemented forwarding unit and hazard detection unit
- 7/7 unit tests PASSED

### Session 2 (2025-10-10 PM)
- Integrated pipelined core
- Added WB-to-ID forwarding (3rd level)
- 7/7 Phase 1 custom tests PASSED
- Created RAW hazard tests

### Session 3 (2025-10-10 Evening)
- **Fixed control hazard bug** (critical)
- Ran full RV32UI compliance suite
- Results: 24/42 PASSED (57%)
- Identified data forwarding not working

---

## Next Steps

### Priority 1: Fix Data Forwarding (Target: +7 tests)
**Tests to fix:** and, or, xor, sra, srai, srl, srli

**Hypothesis:**
- WB-to-ID forwarding timing issue
- Register file write/read timing mismatch
- Forwarding mux priority incorrect

**Debug Approach:**
1. Create minimal failing AND test
2. Analyze waveform
3. Trace WB-to-ID forwarding signals
4. Check register file timing
5. Fix forwarding logic

### Priority 2: Fix Load-Use Hazards (Target: +5 tests)
**Tests to fix:** lb, lbu, lh, lhu, lw

**Hypothesis:**
- Hazard detection not triggering
- Stall/bubble not inserted correctly
- PC stall timing issue

**Debug Approach:**
1. Create minimal load-use test
2. Analyze hazard detection signals
3. Check stall/bubble timing
4. Fix hazard detection logic

### Priority 3: Debug Stores (Target: +3 tests)
**Tests to fix:** sb, sh, sw

**Hypothesis:**
- Related to data forwarding
- Store data path issue
- Memory write timing

**Debug Approach:**
1. Analyze store test failures
2. Check forwarding to stores
3. Verify memory write path

### Target Result
- **Current**: 24/42 (57%)
- **After fixes**: 39/42 (93%)
- **Remaining**: 3 tests (fence_i, ma_data, ld_st - expected failures)

---

## Test Environment

**Simulator**: Icarus Verilog 11.0
**Toolchain**: riscv64-unknown-elf-gcc 10.2.0
**Test Source**: https://github.com/riscv/riscv-tests (RV32UI suite)
**Test Location**: `/tmp/riscv-tests/isa/rv32ui-p-*`
**Logs**: `sim/compliance/*.log`

**Test Execution:**
```bash
./tools/run_compliance_pipelined.sh
```

---

## Conclusion

The pipelined core has had its control hazards fixed and now matches Phase 1 baseline performance (57%). However, the data forwarding and load-use hazard handling are not yet functional, despite being implemented. The next session will focus on debugging why these mechanisms aren't working and achieving the target 93%+ pass rate.

**Key Achievement**: Control hazard bug fixed - all branches and jumps now work correctly! 🎉

**Next Challenge**: Make the data forwarding actually eliminate RAW hazards! 🚀
