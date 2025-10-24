# Privilege Mode Test Suite - Implementation Checklist

**Project**: RV32IMAFDC Enhanced Privilege Testing
**Target**: 34 new privilege mode tests
**Status**: Ready to Begin

---

## 📋 Pre-Implementation Setup

- [x] Macro library created (`tests/asm/include/priv_test_macros.s`)
- [x] Documentation written (Analysis, Plan, Macro docs)
- [x] Demo test created (`test_priv_macros_demo.s`)
- [x] Gap analysis complete
- [ ] **Next session: Begin Phase 1**

---

## Phase 1: U-Mode Fundamentals (6 tests) 🔴 CRITICAL

**Priority**: HIGHEST | **Time**: 2-3 hours | **Status**: ⏭️ Ready

### Tests
- [ ] **1.1** `test_umode_entry_from_mmode.s` - M→U transition via MRET
- [ ] **1.2** `test_umode_entry_from_smode.s` - S→U transition via SRET
- [ ] **1.3** `test_umode_ecall.s` - ECALL from U-mode (cause 8)
- [ ] **1.4** `test_umode_csr_violation.s` - All CSR accesses trap
- [ ] **1.5** `test_umode_illegal_instr.s` - MRET/SRET/WFI trap
- [ ] **1.6** `test_umode_memory_sum.s` - SUM bit controls access

### Validation
- [ ] All 6 tests compile without errors
- [ ] At least 5/6 tests pass (1 may SKIP if MMU incomplete)
- [ ] `make test-quick` still passes (no regressions)
- [ ] Tests appear in `docs/TEST_CATALOG.md`

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/6
Issues found: ___________________
```

---

## Phase 2: Status Register State Machine (5 tests) 🟠 HIGH

**Priority**: HIGH | **Time**: 1-2 hours | **Status**: ⏸️ Pending Phase 1

### Tests
- [ ] **2.1** `test_mstatus_state_mret.s` - MRET state transitions
- [ ] **2.2** `test_mstatus_state_sret.s` - SRET state transitions
- [ ] **2.3** `test_mstatus_state_trap.s` - Trap entry state updates
- [ ] **2.4** `test_mstatus_nested_traps.s` - Nested trap handling
- [ ] **2.5** `test_mstatus_interrupt_enables.s` - MIE/SIE behavior

### Validation
- [ ] All 5 tests compile
- [ ] All 5 tests pass
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/5
Issues found: ___________________
```

---

## Phase 3: Interrupt Handling (6 tests) 🟠 HIGH

**Priority**: HIGH | **Time**: 2-3 hours | **Status**: ⏸️ Pending Phase 2

**Note**: May need to defer if interrupt HW support not available

### Tests
- [ ] **3.1** `test_interrupt_mtimer.s` - Machine timer interrupt
- [ ] **3.2** `test_interrupt_delegation.s` - Interrupt delegation via mideleg
- [ ] **3.3** `test_interrupt_priority.s` - Interrupt vs exception priority
- [ ] **3.4** `test_interrupt_pending.s` - mip/sip pending bits
- [ ] **3.5** `test_interrupt_masking.s` - mie/sie masking
- [ ] **3.6** `test_interrupt_nested.s` - Nested interrupts

### Validation
- [ ] All 6 tests compile
- [ ] Tests pass OR marked as SKIP/TODO if HW support missing
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/6
HW support available: YES / NO / PARTIAL
Issues found: ___________________
```

---

## Phase 4: Exception Coverage (8 tests) 🟡 MEDIUM

**Priority**: MEDIUM | **Time**: 2-3 hours | **Status**: ⏸️ Pending Phase 3

### Tests
- [ ] **4.1** `test_exception_breakpoint.s` - EBREAK (cause 3)
- [ ] **4.2** `test_exception_all_ecalls.s` - ECALL from M/S/U
- [ ] **4.3** `test_exception_load_misaligned.s` - Misaligned load (cause 4)
- [ ] **4.4** `test_exception_store_misaligned.s` - Misaligned store (cause 6)
- [ ] **4.5** `test_exception_fetch_misaligned.s` - Misaligned fetch (cause 0)
- [ ] **4.6** `test_exception_page_fault.s` - Page faults (12/13/15)
- [ ] **4.7** `test_exception_priority.s` - Exception priority
- [ ] **4.8** `test_exception_delegation_full.s` - Full delegation test

### Validation
- [ ] All 8 tests compile
- [ ] Most tests pass (some may SKIP if MMU incomplete or HW supports misaligned)
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/8
Tests skipped: _____ (reasons: _____________)
Issues found: ___________________
```

---

## Phase 5: CSR Edge Cases (4 tests) 🟡 MEDIUM

**Priority**: MEDIUM | **Time**: 1-2 hours | **Status**: ⏸️ Pending Phase 4

### Tests
- [ ] **5.1** `test_csr_readonly_verify.s` - Read-only CSRs immutable
- [ ] **5.2** `test_csr_sstatus_masking.s` - sstatus vs mstatus
- [ ] **5.3** `test_csr_warl_fields.s` - WARL constraints
- [ ] **5.4** `test_csr_side_effects.s` - CSR write side effects

### Validation
- [ ] All 4 tests compile
- [ ] All 4 tests pass
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/4
Issues found: ___________________
```

---

## Phase 6: Delegation Edge Cases (3 tests) 🟢 LOW

**Priority**: LOW | **Time**: 1 hour | **Status**: ⏸️ Pending Phase 5

### Tests
- [ ] **6.1** `test_delegation_to_current_mode.s` - Delegate to current mode
- [ ] **6.2** `test_delegation_priority.s` - Multiple exceptions
- [ ] **6.3** `test_delegation_disable.s` - Clear delegation

### Validation
- [ ] All 3 tests compile
- [ ] All 3 tests pass
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/3
Issues found: ___________________
```

---

## Phase 7: Stress & Regression (2 tests) 🟢 LOW

**Priority**: LOW | **Time**: 1 hour | **Status**: ⏸️ Pending Phase 6

### Tests
- [ ] **7.1** `test_priv_rapid_switching.s` - Rapid M↔S↔U transitions
- [ ] **7.2** `test_priv_comprehensive.s` - All-in-one regression

### Validation
- [ ] Both tests compile
- [ ] Both tests pass
- [ ] `make test-quick` passes
- [ ] Catalog updated

### Session Notes
```
Date: ___________
Duration: ___________
Tests completed: ___/2
Issues found: ___________________
```

---

## 📊 Overall Progress Tracker

### Test Count
- **Total Planned**: 34 tests
- **Implemented**: ___/34 (___%)
- **Passing**: ___/34 (___%)
- **Skipped**: ___/34 (reasons: _____________)
- **Failed**: ___/34 (reasons: _____________)

### Time Tracking
- **Estimated Total**: 10-15 hours
- **Actual Total**: _____ hours
- **Efficiency**: _____ tests/hour

### Phase Completion
- [x] Phase 0: Infrastructure (Macros, Docs)
- [ ] Phase 1: U-Mode (6 tests)
- [ ] Phase 2: State Machine (5 tests)
- [ ] Phase 3: Interrupts (6 tests)
- [ ] Phase 4: Exceptions (8 tests)
- [ ] Phase 5: CSR Edge Cases (4 tests)
- [ ] Phase 6: Delegation (3 tests)
- [ ] Phase 7: Stress (2 tests)

### Quality Metrics
- [ ] All official tests still pass (81/81)
- [ ] `make test-quick` passes
- [ ] No RTL regressions
- [ ] All new tests documented in catalog
- [ ] Implementation matches plan

---

## 🐛 Issues & Bugs Found

Track any RTL bugs or issues discovered during testing:

### Issue 1
- **Test**: ___________________
- **Description**: ___________________
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Status**: OPEN / FIXED / WORKAROUND
- **Fix**: ___________________

### Issue 2
- **Test**: ___________________
- **Description**: ___________________
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Status**: OPEN / FIXED / WORKAROUND
- **Fix**: ___________________

### Issue 3
- **Test**: ___________________
- **Description**: ___________________
- **Severity**: CRITICAL / HIGH / MEDIUM / LOW
- **Status**: OPEN / FIXED / WORKAROUND
- **Fix**: ___________________

---

## ✅ Final Validation Checklist

Complete after all phases:

### Code Quality
- [ ] All tests follow template structure
- [ ] All tests use macro library
- [ ] All tests have proper comments
- [ ] Code is properly formatted

### Testing
- [ ] Official tests: 81/81 passing
- [ ] Quick regression: PASS
- [ ] Custom tests: ___/127+ passing
- [ ] Privilege tests: ___/34 passing

### Documentation
- [ ] `docs/TEST_CATALOG.md` updated (via `make catalog`)
- [ ] `docs/PRIVILEGE_TESTING_RESULTS.md` created
- [ ] `CLAUDE.md` updated with final statistics
- [ ] `README.md` updated if needed
- [ ] All session notes filled in

### Repository
- [ ] All tests committed
- [ ] All docs committed
- [ ] Descriptive commit messages
- [ ] Changes pushed to remote
- [ ] No temporary/debug files left

---

## 🎯 Success Criteria

Mark when achieved:

- [ ] **Minimum**: 32/34 tests passing (94%)
- [ ] **Target**: 34/34 tests passing (100%)
- [ ] **Coverage**: All privilege modes (M/S/U) tested
- [ ] **Coverage**: All 15 exception causes tested
- [ ] **Coverage**: State machine verified
- [ ] **Quality**: No regressions in existing tests
- [ ] **Quality**: Code follows project standards
- [ ] **Docs**: Complete and accurate

---

## 📝 Session Planning Template

Copy this for each implementation session:

```markdown
## Session ___: Phase ___

**Date**: __________
**Time**: Start _____ | End _____ | Duration _____
**Goal**: __________

### Pre-Session
- [ ] Reviewed plan document
- [ ] Ran `make test-quick` (baseline: PASS/FAIL)
- [ ] Reviewed macro library documentation
- [ ] Environment ready

### Tests Implemented
- [ ] Test X.Y: _________ (STATUS: PASS/FAIL/SKIP)
- [ ] Test X.Y: _________ (STATUS: PASS/FAIL/SKIP)
- [ ] Test X.Y: _________ (STATUS: PASS/FAIL/SKIP)

### Issues Encountered
1. __________
2. __________

### Workarounds/Fixes
1. __________
2. __________

### Post-Session
- [ ] Ran `make test-quick` (result: PASS/FAIL)
- [ ] Tests committed
- [ ] Checklist updated
- [ ] Notes documented

### Next Session Plan
1. __________
2. __________

### Time Breakdown
- Planning: _____ min
- Coding: _____ min
- Debugging: _____ min
- Validation: _____ min
- Documentation: _____ min
```

---

## 🔧 Quick Command Reference

```bash
# Start of session
make test-quick                    # Baseline regression

# Build single test
tools/assemble.sh tests/asm/[test].s

# Run single test
tools/run_test.sh [test_name]

# Run all custom tests
make test-custom-all

# Update catalog
make catalog

# Check catalog
cat docs/TEST_CATALOG.md | grep -A2 "test_umode"

# End of session
make test-quick                    # Verify no regressions
git status                         # Review changes
```

---

## 📚 Reference Documents

Quick links to key documentation:

- **Implementation Plan**: `docs/PRIVILEGE_TEST_IMPLEMENTATION_PLAN.md`
- **Gap Analysis**: `docs/PRIVILEGE_TEST_ANALYSIS.md`
- **Macro Library**: `docs/PRIVILEGE_MACRO_LIBRARY.md`
- **Macro Reference**: `tests/asm/include/README.md`
- **RISC-V Priv Spec**: https://riscv.org/technical/specifications/

---

**Document Version**: 1.0
**Created**: 2025-10-23
**Last Updated**: ___________
**Completion Status**: ___/34 tests (___%)
