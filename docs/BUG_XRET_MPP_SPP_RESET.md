# Bug Report: xRET MPP/SPP Reset Issue

**Date**: 2025-10-24
**Status**: 🔴 CRITICAL BUG IDENTIFIED - Fix ready for next session
**Component**: CSR Unit (csr_file.v)
**Impact**: HIGH - Prevents U-mode privilege testing

---

## Summary

After MRET/SRET execution, the CSR unit unconditionally resets MPP/SPP to the highest privilege level (M-mode/S-mode), preventing transitions to lower privilege modes. This violates the RISC-V privileged spec which requires MPP/SPP to be set to the least-privileged supported mode after xRET.

---

## Symptom

**Test Case**: `test_xret_privilege_trap.s` and `test_mret_umode_minimal.s`
**Observed**: Tests timeout with infinite MRET loops
**Expected**: MRET in U-mode should trap with illegal instruction exception

**Debug Output**:
```
[CSR_DEBUG] MSTATUS write: value=00000000 MPP[12:11]=11->00
[PRIV_DEBUG] MRET_FLUSH: priv 11->11 (from MPP)  <-- Should be 11->00!
```

Software successfully writes MPP=00, but MRET reads MPP=11.

---

## Root Cause Analysis

### Investigation Steps

1. ✅ **Verified xRET privilege checking logic** (exception_unit.v:95-101)
   - MRET violation: `current_priv != 2'b11` ✓
   - SRET violation: `current_priv == 2'b00` ✓
   - Both properly combined into `id_illegal_combined` ✓

2. ✅ **Verified exception priority encoder** (exception_unit.v:182-186)
   - Illegal instruction exceptions (including xRET violations) handled correctly ✓

3. ✅ **Verified privilege mode state machine** (rv32i_core_pipelined.v:488-512)
   - Updates correctly on trap/MRET/SRET ✓

4. ✅ **Added comprehensive debug output**
   - Exception unit: xRET detection and violation tracking
   - Core: Privilege mode transitions
   - Pipeline: Exception propagation
   - CSR: mstatus writes with MPP tracking

5. ✅ **Identified the bug** (csr_file.v:494, 499)

### The Bug

**File**: `rtl/core/csr_file.v`
**Lines**: 494 (MRET), 499 (SRET)

```verilog
// Current (BUGGY) implementation:
end else if (mret) begin
    // MRET: Return from machine-mode trap
    mstatus_mie_r  <= mstatus_mpie_r;   // Restore interrupt enable
    mstatus_mpie_r <= 1'b1;             // Set MPIE to 1
    mstatus_mpp_r  <= 2'b11;            // ❌ BUG: Always sets MPP to M-mode
end else if (sret) begin
    // SRET: Return from supervisor-mode trap
    mstatus_sie_r  <= mstatus_spie_r;   // Restore supervisor interrupt enable
    mstatus_spie_r <= 1'b1;             // Set SPIE to 1
    mstatus_spp_r  <= 1'b0;             // ✓ Correctly sets SPP to U-mode
```

**Problem**: MRET unconditionally sets MPP=11 (M-mode), overriding any software-written value.

**Impact**:
- Software writes MPP=00 to prepare for U-mode entry
- MRET reads the old MPP value for privilege restoration
- MRET then immediately sets MPP=11 for the next xRET
- Next MRET always returns to M-mode, creating an infinite loop
- MRET in U-mode never gets executed because we never actually enter U-mode

---

## RISC-V Specification

**Privileged Spec v1.12, Section 3.3.1** (mstatus register):

> "When executing an xRET instruction, supposing xPP holds the value y, xIE is set to xPIE; the privilege mode is changed to y; xPIE is set to 1; and xPP is set to the least-privileged supported mode (U if U-mode is implemented, else M)."

**Key Point**: After xRET, xPP (MPP/SPP) must be set to:
- **U-mode (00)** if U-mode is implemented ← We support this!
- **M-mode (11)** only if U-mode is NOT implemented

---

## The Fix

### Changes Required

**File**: `rtl/core/csr_file.v`

**Line 494** (MRET post-action):
```verilog
// BEFORE (Bug):
mstatus_mpp_r  <= 2'b11;            // Set MPP to M-mode

// AFTER (Fix):
mstatus_mpp_r  <= 2'b00;            // Set MPP to U-mode (least privileged)
```

**Line 499** (SRET post-action):
```verilog
// Already correct!
mstatus_spp_r  <= 1'b0;             // Set SPP to U-mode
```

### Rationale

1. **Compliance**: Matches RISC-V privileged spec requirement
2. **Functionality**: Enables proper U-mode operation via MRET
3. **Symmetry**: Makes MRET behavior consistent with SRET (which already sets SPP=0)
4. **Minimal**: One-line change, no logic complexity

### Test Impact

After fix:
- ✅ `test_mret_umode_minimal.s` will PASS (MRET enters U-mode, second MRET traps)
- ✅ `test_xret_privilege_trap.s` will PASS (all 3 sub-tests succeed)
- ✅ All existing passing tests remain unaffected (they don't rely on MPP=11 after MRET)

---

## Verification Plan

### Before Fix
```bash
make test-quick  # Ensure baseline passes
```

### After Fix (Next Session)

1. **Apply the one-line fix** to csr_file.v:494

2. **Run new privilege tests**:
```bash
env XLEN=32 ./tools/test_pipelined.sh test_mret_umode_minimal
env XLEN=32 ./tools/test_pipelined.sh test_xret_privilege_trap
```
Expected: Both tests PASS with 0xDEADBEEF in t3

3. **Run full regression**:
```bash
make test-quick                           # Quick smoke test
env XLEN=32 ./tools/run_official_tests.sh all  # Full compliance (81 tests)
```
Expected: All tests continue to PASS

4. **Run Phase 1 privilege tests**:
```bash
env XLEN=32 ./tools/test_pipelined.sh test_umode_entry_from_mmode
env XLEN=32 ./tools/test_pipelined.sh test_umode_entry_from_smode
env XLEN=32 ./tools/test_pipelined.sh test_umode_ecall
env XLEN=32 ./tools/test_pipelined.sh test_umode_csr_violation
env XLEN=32 ./tools/test_pipelined.sh test_umode_illegal_instr
```
Expected: All 5 tests PASS

---

## Files Modified (Debug Code - To Be Cleaned)

### Debug additions (temporary):
1. **rtl/core/exception_unit.v**:
   - Added `clk` input (conditional on DEBUG_XRET_PRIV)
   - Added xRET violation debug displays (lines 101-114)
   - Added exception raise debug display (lines 200-204)

2. **rtl/core/rv32i_core_pipelined.v**:
   - Added clock to exception_unit instantiation (lines 1451-1453)
   - Added privilege mode transition debug (lines 495-509)
   - Added EXMEM pipeline debug (lines 1556-1567)

3. **rtl/core/csr_file.v**:
   - Added MSTATUS write debug (lines 504-507)

### Test files created:
- `tests/asm/test_mret_umode_minimal.s` (minimal reproduction case)
- `tests/asm/test_mret_umode_minimal.hex`

### Next Session TODO:
- [ ] Remove all `DEBUG_XRET_PRIV` conditional debug code
- [ ] Apply the one-line fix to csr_file.v:494
- [ ] Run verification plan
- [ ] Update PHASES.md with results
- [ ] Commit with proper message

---

## Related Files

- Bug location: `rtl/core/csr_file.v:494`
- Tests: `tests/asm/test_xret_privilege_trap.s`, `tests/asm/test_mret_umode_minimal.s`
- Spec reference: RISC-V Privileged Spec v1.12, Section 3.3.1

---

## Historical Context

- **Phase 1 Status**: 5/6 U-mode tests passing (test_umode_memory_sum skipped)
- **Current Blocker**: This bug prevents proper MRET→U-mode transitions
- **Impact**: Cannot test MRET privilege violations, blocking Phase 2 progress

---

## Additional Notes

### Why This Bug Wasn't Caught Earlier

1. **Official compliance tests**: All start and end in M-mode, never test M→U→M transitions via MRET
2. **Existing privilege tests**: Used SRET for U-mode entry (which works correctly)
3. **MRET tests**: Primarily tested M→M transitions, which worked despite the bug

### Why SRET Works But MRET Doesn't

SRET already correctly sets SPP=0 (line 499), following the spec. The MRET implementation simply didn't follow the same pattern.

---

**Ready for fix in next session!** 🚀
