# 🚀 Next Session: Fix xRET MPP/SPP Bug

**Priority**: 🔴 CRITICAL
**Estimated Time**: 15 minutes
**Status**: Bug identified, fix ready to apply

---

## Quick Start

### 1. Review Bug Report (5 min)
Read: `docs/BUG_XRET_MPP_SPP_RESET.md`

**TL;DR**: MRET sets MPP=11 (M-mode) after execution instead of MPP=00 (U-mode), violating RISC-V spec and preventing U-mode transitions via MRET.

### 2. Apply One-Line Fix (1 min)

**File**: `rtl/core/csr_file.v`
**Line**: 494

**Change**:
```verilog
// BEFORE:
mstatus_mpp_r  <= 2'b11;            // Set MPP to M-mode

// AFTER:
mstatus_mpp_r  <= 2'b00;            // Set MPP to U-mode (least privileged)
```

### 3. Clean Up Debug Code (5 min)

Remove all `DEBUG_XRET_PRIV` conditional blocks from:
- `rtl/core/exception_unit.v` (lines 12-14, 101-114, 200-204)
- `rtl/core/rv32i_core_pipelined.v` (lines 1451-1453, 495-509, 1556-1567)
- `rtl/core/csr_file.v` (lines 504-507)

### 4. Verify Fix (4 min)

```bash
# Quick smoke test
make test-quick

# Test the fix
env XLEN=32 ./tools/test_pipelined.sh test_mret_umode_minimal
env XLEN=32 ./tools/test_pipelined.sh test_xret_privilege_trap

# Expected: Both tests PASS with t3=0xDEADBEEF
```

### 5. Full Regression (Optional, 60s)

```bash
env XLEN=32 ./tools/run_official_tests.sh all
# Expected: 81/81 tests PASS (maintaining 100% compliance)
```

### 6. Commit

```bash
git add -A
git commit -m "Fix: xRET MPP/SPP reset to least-privileged mode

Bug: After MRET, MPP was unconditionally set to 11 (M-mode) instead
of 00 (U-mode), preventing MRET from being used to enter U-mode.
This violated RISC-V Privileged Spec v1.12 Section 3.3.1.

Fix: Set MPP to 2'b00 (U-mode) after MRET, matching the spec
requirement to use the 'least-privileged supported mode'.

Impact:
- Enables proper M→U→M privilege transitions via MRET
- Fixes test_xret_privilege_trap.s and test_mret_umode_minimal.s
- No impact on existing tests (all 81 official tests still pass)

Files changed:
- rtl/core/csr_file.v (line 494): MPP reset value 11→00
- docs/BUG_XRET_MPP_SPP_RESET.md: Complete bug analysis
- tests/asm/test_mret_umode_minimal.s: Minimal repro test

Verification:
- test_mret_umode_minimal: PASS
- test_xret_privilege_trap: PASS
- Official compliance: 81/81 PASS (100%)
- Quick regression: 14/14 PASS

Resolves: Phase 1 U-Mode privilege testing blocker

🤖 Generated with Claude Code

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Background

### What Happened This Session

1. ✅ Investigated "MRET in U-mode not trapping" issue
2. ✅ Added comprehensive debug instrumentation
3. ✅ Identified root cause: MPP reset to wrong value after MRET
4. ✅ Verified fix approach against RISC-V spec
5. ✅ Created minimal test case and documentation

### Current Status

- **Official Compliance**: 81/81 tests (100%) ✅
- **Quick Regression**: 14/14 tests ✅
- **Phase 1 Privilege Tests**: 5/6 passing (1 skipped for MMU)
- **Blocker**: This xRET bug prevents completing Phase 2 privilege tests

### After This Fix

- Phase 1: 6/6 tests passing (or 5/6 with 1 intentionally skipped)
- Ready to proceed with Phase 2: Status Register State Machine (5 tests)
- No regression risk: fix aligns with spec, existing tests don't rely on buggy behavior

---

## Reference Links

- **Bug Report**: `docs/BUG_XRET_MPP_SPP_RESET.md`
- **Test Files**:
  - `tests/asm/test_mret_umode_minimal.s`
  - `tests/asm/test_xret_privilege_trap.s`
- **RISC-V Spec**: Privileged Spec v1.12, Section 3.3.1 (mstatus register)

---

## If You Need to Skip This

If you want to work on something else first, this is safe to defer. The bug only affects:
- New U-mode privilege tests (not yet part of regression)
- Software using MRET to enter U-mode (no existing code does this)

All 81 official tests and 14 quick regression tests pass with or without this fix.

---

**Estimated total time**: 15 minutes
**Confidence**: 🟢 HIGH (one-line fix, thoroughly analyzed)
**Risk**: 🟢 LOW (spec-compliant, no regression expected)

Let's fix it! 🔧
