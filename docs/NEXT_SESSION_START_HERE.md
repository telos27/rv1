# Next Session: Start Here 🚀

**Date**: Session 89 (next session after 2025-11-04)
**Phase**: Phase 4 Prep - Test Implementation
**Status**: Ready to begin simplified incremental test development

---

## Quick Context

### What We Accomplished (Session 88)
✅ Analyzed test coverage gaps (44 tests needed)
✅ Created comprehensive test plan (3-4 weeks, all priorities)
✅ Decided on Option A: implement ALL 44 tests before xv6
✅ Created 2,397 lines of planning documentation
✅ Implemented first test (`test_sum_basic.s` - PASSES ✅)
✅ Tagged v1.0-rv64-complete milestone
✅ All changes pushed to GitHub

### Current State
- **Official Tests**: 187/187 (100% pass) - RV32/RV64 IMAFDC ✅
- **Custom Tests**: 231 tests, 1/44 new tests working
- **Git**: Clean, all changes committed and pushed
- **Next Milestone**: v1.1-xv6-ready (after 44 tests)

---

## Next Session Plan: Simplified Incremental Approach

### Strategy: Build Complexity Gradually

**Phase 1: CSR/Bit Tests (Simple, no VM)**
Start here ← YOU ARE HERE 👈

1. ✅ `test_sum_basic.s` - DONE (toggle SUM bit)
2. ⏭️ `test_mxr_basic.s` - Toggle MXR bit
3. ⏭️ `test_sum_mxr_csr.s` - Combined SUM+MXR CSR test

**Phase 2: Simple VM (Identity mapping)**
4. `test_vm_identity_permissions.s` - R/W/X/U bits with identity mapping
5. `test_vm_identity_sum.s` - SUM behavior with identity-mapped pages

**Phase 3: Non-Identity VM (Real translations)**
6. `test_vm_non_identity_simple.s` - VA→PA mapping
7. `test_sum_with_translation.s` - SUM with real page translation

**Phase 4: Trap Handling**
8. `test_page_fault_simple.s` - Basic page fault generation
9. `test_sum_disabled.s` (revised) - S-mode U-page fault
10. Continue with remaining 34 tests...

---

## Recommended Starting Point

### Test #2: `test_mxr_basic.s`

**Purpose**: Verify MSTATUS.MXR bit (bit 19) can be toggled

**Template** (based on working `test_sum_basic.s`):
```assembly
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Enable MXR bit
    li      t0, MSTATUS_MXR         # 0x80000 = bit 19
    csrrs   zero, mstatus, t0

    TEST_STAGE 2

    # Verify MXR bit is set
    csrr    t1, mstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # Should be set

    TEST_STAGE 3

    # Clear MXR bit
    li      t0, MSTATUS_MXR
    csrrc   zero, mstatus, t0

    TEST_STAGE 4

    # Verify MXR bit is clear
    csrr    t1, mstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # Should be clear

    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

**Run**:
```bash
env XLEN=32 timeout 5s ./tools/run_test_by_name.sh test_mxr_basic
```

**Expected**: Should pass quickly (similar to test_sum_basic)

---

## Key Files to Reference

### Planning Documents
- `docs/PHASE_4_PREP_TEST_PLAN.md` - Complete 44-test plan
- `docs/PHASE_4_OS_READINESS_ANALYSIS.md` - Gap analysis details
- `docs/SESSION_88_PHASE4_PREP_START.md` - Session 88 summary

### Working Test Example
- `tests/asm/test_sum_basic.s` - Template for simple CSR tests

### Test Infrastructure
- `tests/asm/include/priv_test_macros.s` - Macro library
- `tools/run_test_by_name.sh` - Test runner script
- `make test-quick` - Quick regression (14 tests)

---

## Session 89 Goals

### Minimum (Quick Session)
- [ ] Implement `test_mxr_basic.s` ✅
- [ ] Verify it passes
- [ ] Commit and push

### Ideal (Productive Session)
- [ ] Complete Phase 1: All 3 CSR/bit tests
  - [ ] `test_mxr_basic.s`
  - [ ] `test_sum_mxr_csr.s` (combined test)
- [ ] Start Phase 2: First VM test
- [ ] 3-4 tests total working

### Stretch (Great Session)
- [ ] Complete Phase 1 & Phase 2 (5 tests total)
- [ ] Start Phase 3 (non-identity VM)
- [ ] 5-7 tests working

---

## Quick Commands Reference

```bash
# Create new test
vim tests/asm/test_mxr_basic.s

# Run single test
env XLEN=32 timeout 5s ./tools/run_test_by_name.sh test_mxr_basic

# Quick regression
make test-quick

# Full RV32 compliance
env XLEN=32 ./tools/run_official_tests.sh all

# Check git status
git status

# Commit when ready
git add tests/asm/test_*.s
git commit -m "Session 89: <describe tests added>"
git push origin main
```

---

## Debug Tips (If Tests Fail)

### Test Times Out
- Check x29 (stage register) to see where it stopped
- Add more TEST_STAGE markers
- Verify no infinite loops
- Check PC value at timeout

### Test Fails
- Check x28 value (should be 0xDEADBEEF for pass, 0xDEADDEAD for fail)
- Add debug output with TEST_STAGE
- Verify CSR bit positions (SUM=18, MXR=19)
- Check macro expansions

### Compilation Errors
- Verify .include path is correct
- Check macro names match library
- Ensure .option norvc if not using compressed

---

## Progress Tracking

**Overall**: 3/44 tests working (6.8%)

**Phase 1 - CSR Tests**: 3/3 COMPLETE ✅
- ✅ test_sum_basic.s (Session 88)
- ✅ test_mxr_basic.s (Session 89)
- ✅ test_sum_mxr_csr.s (Session 89)

**Week 1 (Priority 1A)**: 3/10 tests
- ⏭️ 7 more tests (VM, TLB)

**Estimated Time**:
- Simple CSR tests: 30-60 min each
- Simple VM tests: 1-2 hours each
- Complex tests: 2-4 hours each

---

## Success Criteria

### This Test Working
- ✅ Assembles without errors
- ✅ Runs to completion (no timeout)
- ✅ x28 = 0xDEADBEEF (TEST_PASS)
- ✅ Takes < 1000 cycles

### Session Success
- ✅ At least 1 new test passing
- ✅ No regressions (make test-quick still passes)
- ✅ Changes committed and pushed
- ✅ Documentation updated

---

## Let's Go! 🚀

**Start with**: `test_mxr_basic.s` (simple CSR toggle, 60 lines, 30 min)

**Remember**: Keep it simple, build incrementally, test often!

Good luck! 💪
