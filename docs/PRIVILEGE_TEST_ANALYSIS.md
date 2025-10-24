# Privilege Mode Testing - Gap Analysis & Enhancement Plan

**Date**: 2025-10-23
**Status**: Analysis Complete - Ready for Implementation

## Executive Summary

This document analyzes the current privilege mode testing coverage for the RV32IMAFDC core and identifies gaps that need comprehensive testing to ensure robustness of the M/S/U privilege architecture.

## Current Test Coverage Analysis

### Existing Tests (18 privilege-related tests found)

**Basic Privilege Tests:**
- `test_priv_check.s` - Basic M→S transition via MRET
- `test_priv_minimal.s` - Minimal privilege checking
- `test_priv_basic.s` - Basic privilege operations
- `test_priv_transitions.s` - M→S→M transitions with illegal instruction trap

**CSR Access Tests:**
- `test_simple_csr.s` - Simple CSR operations
- `test_csr_basic.s` - Basic CSR read/write
- `test_csr_debug.s` - CSR debugging
- `test_fp_csr.s` - Floating-point CSR operations
- `test_smode_csr.s` - S-mode CSR access

**Trap & Exception Tests:**
- `test_ecall_simple.s` - Simple ECALL test
- `test_ecall_smode.s` - ECALL from S-mode
- `test_mret_simple.s` - MRET instruction
- `test_sret.s` - SRET instruction
- `test_phase10_2_sret.s` - Enhanced SRET testing

**Delegation Tests:**
- `test_medeleg.s` - MEDELEG CSR test
- `test_phase10_2_delegation.s` - Trap delegation to S-mode
- `test_phase10_2_priv_violation.s` - CSR privilege violations

**Comprehensive Tests:**
- `test_supervisor_basic.s` - Basic supervisor mode
- `test_supervisor_complete.s` - Comprehensive supervisor test (8 test stages)

### What's Already Working Well

✅ **M-mode to S-mode transitions** - MRET with MPP setting
✅ **S-mode to M-mode transitions** - ECALL and illegal instruction exceptions
✅ **CSR privilege checking** - Illegal access detection (csr_priv_ok in rtl/core/csr_file.v:371)
✅ **Exception delegation** - medeleg/mideleg basic functionality
✅ **Supervisor CSR access** - sstatus, sie, stvec, sscratch, sepc, scause, stval, sip
✅ **Trap vector handling** - mtvec/stvec

## Identified Gaps in Test Coverage

### 🔴 Critical Gaps (Must Test)

#### 1. **User Mode (U-mode) Testing** - **HIGHEST PRIORITY**
**Current Status**: Minimal/no U-mode testing
**Risk**: U-mode implementation exists (MMU checks for `priv_mode == 2'b00`) but is largely untested

**Missing Tests:**
- [ ] M→U transition via MRET (set MPP=00)
- [ ] S→U transition via SRET (set SPP=0)
- [ ] U-mode attempting to access any CSR (should always trap)
- [ ] U-mode ECALL (cause code 8)
- [ ] U-mode attempting privileged instructions (MRET, SRET, WFI)
- [ ] U-mode memory access (interaction with SUM bit in mstatus)

#### 2. **Interrupt Delegation & Handling** - **HIGH PRIORITY**
**Current Status**: Only exception delegation tested (medeleg), no interrupt tests
**Risk**: mideleg and interrupt priority logic untested

**Missing Tests:**
- [ ] mideleg configuration and interrupt delegation to S-mode
- [ ] Machine timer/software/external interrupts (MTI, MSI, MEI)
- [ ] Supervisor timer/software/external interrupts (STI, SSI, SEI)
- [ ] Interrupt priority and nesting
- [ ] Interrupt enable/disable (MIE/SIE bits in mstatus)
- [ ] Interrupt pending flags (mip/sip)
- [ ] Interrupt masking (mie/sie registers)

#### 3. **Status Register State Transitions** - **HIGH PRIORITY**
**Current Status**: Basic MPIE/SPIE tested, but comprehensive state machine untested

**Missing Tests:**
- [ ] MRET: Verify MIE←MPIE, MPIE←1, MPP←U/M (depending on config)
- [ ] SRET: Verify SIE←SPIE, SPIE←1, SPP←U
- [ ] Trap Entry: Verify xPIE←xIE, xIE←0, xPP←current_priv
- [ ] Multiple nested traps and returns (M→S→M with state tracking)
- [ ] MIE/SIE interaction during privilege transitions

#### 4. **CSR Field Constraints & Side Effects** - **MEDIUM PRIORITY**
**Current Status**: Basic read/write tested, but WARL/WLRL semantics untested

**Missing Tests:**
- [ ] mstatus.MPP: Verify can't set to reserved value (10)
- [ ] mstatus.SPP: Verify only bit 0 (can't hold M-mode)
- [ ] mstatus writable bits vs read-only bits (UXL, SXL on RV64)
- [ ] sstatus masking (verify M-mode fields not writable via sstatus)
- [ ] xTVEC mode bits [1:0] (Direct=0, Vectored=1, verify alignment)
- [ ] xEPC alignment (must be 4-byte aligned, or 2-byte if C extension)
- [ ] Side effects: Writing mstatus vs sstatus consistency

#### 5. **Exception Cause Code Coverage** - **MEDIUM PRIORITY**
**Current Status**: Only illegal instruction (2) and ECALL (8, 9) tested

**Missing Exception Tests:**
- [ ] Instruction address misaligned (0)
- [ ] Instruction access fault (1)
- [ ] Breakpoint (3) - EBREAK instruction
- [ ] Load address misaligned (4)
- [ ] Load access fault (5)
- [ ] Store/AMO address misaligned (6)
- [ ] Store/AMO access fault (7)
- [ ] Instruction page fault (12) - with MMU enabled
- [ ] Load page fault (13) - with MMU enabled
- [ ] Store/AMO page fault (15) - with MMU enabled

#### 6. **Delegation Edge Cases** - **MEDIUM PRIORITY**
**Current Status**: Basic delegation tested, but edge cases missing

**Missing Tests:**
- [ ] Delegate exception to S-mode when already in S-mode
- [ ] Delegation with multiple exceptions (verify priority)
- [ ] Verify M-mode exceptions never delegate (e.g., exception in M-mode stays in M)
- [ ] Clear delegation bits and verify trap goes to M-mode
- [ ] Delegation of interrupts vs exceptions (separate medeleg/mideleg)

### 🟡 Medium Priority Gaps

#### 7. **Read-Only CSR Verification**
- [ ] Attempt to write mvendorid, marchid, mimpid, mhartid (verify no change)
- [ ] Attempt to write misa (verify no change, or only legal changes)
- [ ] Verify bits [1:0] of xTVEC are WARL

#### 8. **Privilege-Specific Instruction Behavior**
- [ ] WFI in different privilege modes (legal in M/S, may trap in U)
- [ ] SFENCE.VMA privilege checking (S-mode instruction)
- [ ] Verify privileged instructions decode properly per mode

#### 9. **Cross-Extension Privilege Interaction**
- [ ] Floating-point CSRs (fcsr, frm, fflags) accessible from all modes
- [ ] AMO instructions in U-mode (should work with proper memory permissions)
- [ ] Memory access privilege with MMU (PTE permission bits + SUM/MXR)

### 🟢 Nice-to-Have Enhancements

#### 10. **Stress Testing**
- [ ] Rapid privilege switching (M→S→M→S...)
- [ ] Nested traps at maximum depth
- [ ] Exception during exception handler execution

#### 11. **Negative Testing**
- [ ] Invalid CSR addresses (verify illegal_csr)
- [ ] Write to read-only CSR fields
- [ ] Out-of-range privilege transitions

## Current RTL Privilege Architecture

### Privilege Levels Implemented
```verilog
// From rtl/core/csr_file.v and mmu.v
2'b11 = M-mode (Machine)
2'b01 = S-mode (Supervisor)
2'b00 = U-mode (User)
```

### CSR Privilege Checking (rtl/core/csr_file.v:369-371)
```verilog
wire csr_priv_level = csr_addr[9:8];  // Bits [9:8] of CSR addr encode minimum privilege
wire csr_priv_ok = (current_priv >= csr_priv_level);
assign illegal_csr = csr_we && ((!csr_exists) || (!csr_priv_ok) || csr_read_only);
```

### Status Register State Machine
**mstatus fields:**
- MIE[3], SIE[1] - Current interrupt enable
- MPIE[7], SPIE[5] - Previous interrupt enable
- MPP[12:11], SPP[8] - Previous privilege mode
- SUM[18], MXR[19] - Memory access control

**State transitions (need comprehensive testing):**
- Trap: xPIE←xIE, xIE←0, xPP←current_priv
- xRET: xIE←xPIE, xPIE←1, priv←xPP

## Recommended Test Suite Structure

### Phase 1: U-Mode Fundamentals (6 tests) - **START HERE**
1. `test_umode_entry_from_mmode.s` - M→U via MRET
2. `test_umode_entry_from_smode.s` - S→U via SRET
3. `test_umode_ecall.s` - ECALL from U-mode (cause 8)
4. `test_umode_csr_violation.s` - Any CSR access from U-mode traps
5. `test_umode_illegal_instr.s` - MRET/SRET/WFI from U-mode
6. `test_umode_memory_sum.s` - U-mode memory access with SUM bit

### Phase 2: Status Register State Machine (5 tests)
7. `test_mstatus_state_mret.s` - Verify MRET state transitions
8. `test_mstatus_state_sret.s` - Verify SRET state transitions
9. `test_mstatus_state_trap.s` - Verify trap entry state updates
10. `test_mstatus_nested_traps.s` - Nested M→S→M with state tracking
11. `test_mstatus_interrupt_enables.s` - MIE/SIE bit behavior

### Phase 3: Interrupt Handling (6 tests)
12. `test_interrupt_mtimer.s` - Machine timer interrupt
13. `test_interrupt_delegation.s` - Interrupt delegation via mideleg
14. `test_interrupt_priority.s` - Interrupt vs exception priority
15. `test_interrupt_pending.s` - mip/sip pending bit handling
16. `test_interrupt_masking.s` - mie/sie masking
17. `test_interrupt_nested.s` - Nested interrupt handling

### Phase 4: Exception Coverage (8 tests)
18. `test_exception_breakpoint.s` - EBREAK (cause 3)
19. `test_exception_all_ecalls.s` - ECALL from M/S/U (causes 11, 9, 8)
20. `test_exception_load_misaligned.s` - Misaligned load (cause 4)
21. `test_exception_store_misaligned.s` - Misaligned store (cause 6)
22. `test_exception_fetch_misaligned.s` - Misaligned fetch (cause 0)
23. `test_exception_page_fault.s` - Page faults with MMU (causes 12, 13, 15)
24. `test_exception_priority.s` - Exception priority ordering
25. `test_exception_delegation_full.s` - All delegatable exceptions

### Phase 5: CSR Edge Cases (4 tests)
26. `test_csr_readonly_verify.s` - Verify read-only CSRs immutable
27. `test_csr_sstatus_masking.s` - sstatus vs mstatus aliasing
28. `test_csr_warl_fields.s` - WARL field constraints (MPP, SPP, xTVEC)
29. `test_csr_side_effects.s` - CSR write side effects

### Phase 6: Delegation Edge Cases (3 tests)
30. `test_delegation_to_current_mode.s` - Delegate to S while in S
31. `test_delegation_priority.s` - Multiple exceptions with delegation
32. `test_delegation_disable.s` - Clear delegation, verify M-mode trap

### Phase 7: Stress & Regression (2 tests)
33. `test_priv_rapid_switching.s` - Rapid M→S→U→S→M transitions
34. `test_priv_comprehensive.s` - All-in-one regression test

## Implementation Strategy

### Step 1: Create Test Template
Create a common test harness in `tests/asm/include/priv_test_macros.s`:
```assembly
# Macros for privilege testing
.macro EXPECT_TRAP handler
    la      t0, \handler
    csrw    mtvec, t0
.endm

.macro ENTER_UMODE target
    la      t0, \target
    csrw    mepc, t0
    li      t1, 0xFFFFE7FF
    csrr    t2, mstatus
    and     t2, t2, t1      # Clear MPP
    csrw    mstatus, t2     # MPP = 00 (U-mode)
    mret
.endm
# ... more macros
```

### Step 2: Implement Phase 1 (U-mode) - **CRITICAL**
Start with 6 U-mode tests to establish baseline U-mode functionality.

### Step 3: Implement Phases 2-3 (State & Interrupts)
Focus on interrupt handling infrastructure which is currently untested.

### Step 4: Complete Coverage (Phases 4-7)
Systematically implement remaining tests for comprehensive coverage.

### Step 5: Integration
- Add all new tests to `make test-custom-all`
- Update `docs/TEST_CATALOG.md`
- Create `make test-priv` target for privilege-only tests
- Add to quick regression if tests are fast (<1s each)

## Success Metrics

**Coverage Goals:**
- ✅ All 3 privilege modes (M/S/U) tested in isolation
- ✅ All privilege transitions tested (M↔S↔U)
- ✅ All CSRs tested for privilege violations
- ✅ All exception causes tested (0-15)
- ✅ Interrupt delegation functional
- ✅ Status register state machine verified
- ✅ Edge cases and error conditions covered

**Target**: 34 new comprehensive privilege tests
**Expected Pass Rate**: 100% (fix RTL bugs as discovered)

## Timeline Estimate

- **Phase 1 (U-mode)**: 2-3 hours (6 tests)
- **Phase 2 (State)**: 1-2 hours (5 tests)
- **Phase 3 (Interrupts)**: 2-3 hours (6 tests)
- **Phase 4 (Exceptions)**: 2-3 hours (8 tests)
- **Phase 5 (CSRs)**: 1-2 hours (4 tests)
- **Phase 6 (Delegation)**: 1 hour (3 tests)
- **Phase 7 (Stress)**: 1 hour (2 tests)

**Total Estimated Time**: 10-15 hours for complete implementation

## Next Steps

1. ✅ Review and approve this test plan
2. ⏭️ Create test macro library (`tests/asm/include/priv_test_macros.s`)
3. ⏭️ Implement Phase 1: U-mode tests (6 tests)
4. ⏭️ Run and debug Phase 1
5. ⏭️ Continue with Phases 2-7

---

**Prepared by**: Claude Code AI Assistant
**Review Status**: Pending User Approval
