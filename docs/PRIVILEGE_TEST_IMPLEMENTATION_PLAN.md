# Privilege Mode Test Suite - Complete Implementation Plan

**Project**: RV32IMAFDC Processor Privilege Mode Testing
**Created**: 2025-10-23
**Status**: Ready for Implementation
**Estimated Time**: 10-15 hours total
**Target**: 34 new comprehensive privilege mode tests

---

## Table of Contents
1. [Executive Summary](#executive-summary)
2. [Prerequisites](#prerequisites)
3. [Phase-by-Phase Implementation](#phase-by-phase-implementation)
4. [Test Template & Patterns](#test-template--patterns)
5. [Validation Strategy](#validation-strategy)
6. [Success Criteria](#success-criteria)
7. [Session Planning](#session-planning)

---

## Executive Summary

### Goal
Implement 34 comprehensive privilege mode tests to achieve complete coverage of M/S/U mode functionality, addressing critical gaps identified in the test coverage analysis.

### Current Status
- ✅ Macro library created (520+ lines, 50+ macros)
- ✅ Documentation complete
- ✅ Demo test written
- ✅ Gap analysis complete
- ⏭️ Ready to implement Phase 1

### Critical Gaps to Address
1. **U-mode testing** (almost zero coverage) - HIGHEST PRIORITY
2. **Interrupt handling** (mideleg untested)
3. **State machine transitions** (MPIE/SPIE/MPP/SPP)
4. **Exception cause coverage** (only 2/15 tested)
5. **CSR constraints** (WARL semantics)
6. **Delegation edge cases**

---

## Prerequisites

### Tools & Environment
- ✅ RISC-V toolchain: `riscv64-unknown-elf-{as,ld,objdump}`
- ✅ Icarus Verilog: `iverilog`, `vvp`
- ✅ Test infrastructure: `make test-quick`, `make test-custom-all`
- ✅ Macro library: `tests/asm/include/priv_test_macros.s`

### Documentation References
- `docs/PRIVILEGE_TEST_ANALYSIS.md` - Gap analysis
- `docs/PRIVILEGE_MACRO_LIBRARY.md` - Macro library summary
- `tests/asm/include/README.md` - Macro quick reference
- RISC-V Privileged Spec v1.12

### Before Starting Each Phase
```bash
# 1. Verify test infrastructure works
make test-quick

# 2. Check that macro library is accessible
ls tests/asm/include/priv_test_macros.s

# 3. Review macro documentation
cat tests/asm/include/README.md
```

---

## Phase-by-Phase Implementation

## 📋 PHASE 1: U-Mode Fundamentals (6 tests)

**Priority**: 🔴 CRITICAL
**Estimated Time**: 2-3 hours
**Goal**: Establish baseline U-mode functionality

### Why This Is Critical
U-mode is the least privileged mode and is almost completely untested. The RTL has U-mode support (`priv_mode == 2'b00` in MMU), but without tests, we don't know if it works correctly.

### Tests to Implement

#### Test 1.1: `test_umode_entry_from_mmode.s`
**Purpose**: Verify M→U transition via MRET

**Test Flow**:
```
1. Start in M-mode
2. Set MPP = 00 (U-mode)
3. Set MEPC to U-mode target address
4. Execute MRET
5. Verify execution continues in U-mode
6. Verify can't access any CSRs (should trap)
7. SUCCESS
```

**Implementation Pattern**:
```assembly
.include "tests/asm/include/priv_test_macros.s"

_start:
    TEST_PREAMBLE
    SET_MTVEC_DIRECT m_trap_handler

    # Enter U-mode
    ENTER_UMODE_M umode_code

umode_code:
    # Verify we're in U-mode by attempting CSR access
    # This should trap to M-mode handler
    csrr t0, mstatus    # Illegal in U-mode!
    TEST_FAIL           # Should never reach here

m_trap_handler:
    # Verify cause = illegal instruction
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

**Expected Result**: ✅ PASS - U-mode entry works, CSR access trapped

**Debug If Fails**:
- Check MPP bits are actually cleared
- Verify MRET updates privilege mode
- Check CSR privilege checking logic in RTL

---

#### Test 1.2: `test_umode_entry_from_smode.s`
**Purpose**: Verify S→U transition via SRET

**Test Flow**:
```
1. Start in M-mode
2. Enter S-mode via MRET
3. From S-mode: Set SPP = 0 (U-mode)
4. Set SEPC to U-mode target
5. Execute SRET
6. Verify execution in U-mode
7. Attempt privileged instruction → trap to M-mode
8. SUCCESS
```

**Key Differences from 1.1**:
- Uses SRET instead of MRET
- Uses SPP instead of MPP
- Traps may go to S-mode if delegation is set (test both cases)

**Implementation**:
```assembly
_start:
    TEST_PREAMBLE

    # First enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    # Now enter U-mode from S-mode
    ENTER_UMODE_S umode_code

umode_code:
    # Attempt SRET (privileged instruction)
    sret                # Should trap!
    TEST_FAIL

m_trap_handler:
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail
    TEST_PASS

s_trap_handler:
    TEST_FAIL           # Shouldn't delegate by default

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

---

#### Test 1.3: `test_umode_ecall.s`
**Purpose**: Verify ECALL from U-mode (cause code 8)

**Test Flow**:
```
1. Enter U-mode
2. Execute ECALL
3. Trap to M-mode (or S-mode if delegated)
4. Verify cause = 8 (ECALL from U-mode)
5. Verify MEPC points to ECALL instruction
6. Test with and without delegation
7. SUCCESS
```

**Implementation**:
```assembly
_start:
    TEST_PREAMBLE

    # Test 1: ECALL without delegation (goes to M-mode)
    CLEAR_EXCEPTION_DELEGATION
    ENTER_UMODE_M umode_test1

umode_test1:
    ecall               # Should go to M-mode

m_trap_handler:
    csrr t0, mcause
    li t1, CAUSE_ECALL_U
    bne t0, t1, test_umode_test2_setup  # If not cause 8, try test 2

    # Test 1 passed, now test delegation
    j test_umode_test2_setup

test_umode_test2_setup:
    # Test 2: ECALL with delegation (goes to S-mode)
    DELEGATE_EXCEPTION CAUSE_ECALL_U
    ENTER_SMODE_M smode_code

smode_code:
    ENTER_UMODE_S umode_test2

umode_test2:
    ecall               # Should go to S-mode

s_trap_handler:
    EXPECT_CSR scause, CAUSE_ECALL_U, test_fail
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

---

#### Test 1.4: `test_umode_csr_violation.s`
**Purpose**: Verify ALL CSR accesses from U-mode trap

**Test Flow**:
```
1. Enter U-mode
2. Attempt to read each CSR category:
   - M-mode CSRs (mstatus, mepc, etc.)
   - S-mode CSRs (sstatus, sepc, etc.)
   - U-mode CSRs (should also trap - we don't implement U-mode CSRs)
3. Each attempt should trap with cause = illegal instruction
4. SUCCESS
```

**CSRs to Test**:
- M-mode: mstatus, mie, mtvec, mscratch, mepc, mcause, mtval, mip
- S-mode: sstatus, sie, stvec, sscratch, sepc, scause, stval, sip
- FP CSRs: fcsr, frm, fflags (these might be accessible in U-mode!)

**Implementation**:
```assembly
_start:
    TEST_PREAMBLE
    li s0, 0            # Test counter

    ENTER_UMODE_M umode_code

umode_code:
    # Test 1: M-mode CSR
    csrr t0, mstatus
    TEST_FAIL

m_trap_handler:
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail

    addi s0, s0, 1
    li t0, 1
    beq s0, t0, test_smode_csr

    li t0, 2
    beq s0, t0, test_fp_csr

    # All tests passed
    TEST_PASS

test_smode_csr:
    # Return to U-mode to test S-mode CSR
    csrw mepc, ...      # Set to test S-mode CSR
    RETURN_UMODE_M umode_test2

umode_test2:
    csrr t0, sstatus
    TEST_FAIL

test_fp_csr:
    # FP CSRs might be accessible - verify behavior
    # (Implementation depends on spec interpretation)
    ...

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

---

#### Test 1.5: `test_umode_illegal_instr.s`
**Purpose**: Verify privileged instructions trap in U-mode

**Privileged Instructions to Test**:
- MRET (M-mode only)
- SRET (S-mode and above)
- WFI (behavior depends on mstatus.TW)
- SFENCE.VMA (S-mode and above)

**Test Flow**:
```
1. Enter U-mode
2. Attempt each privileged instruction
3. Verify each causes illegal instruction exception
4. SUCCESS
```

**Implementation**:
```assembly
_start:
    TEST_PREAMBLE
    li s0, 0

    ENTER_UMODE_M umode_code

umode_code:
    li s0, 1
    mret                # Should trap
    TEST_FAIL

m_trap_handler:
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail

    li t0, 1
    beq s0, t0, test_sret
    li t0, 2
    beq s0, t0, test_wfi

    TEST_PASS

test_sret:
    li s0, 2
    csrw mepc, ...
    RETURN_UMODE_M umode_test2

umode_test2:
    sret
    TEST_FAIL

test_wfi:
    li s0, 3
    csrw mepc, ...
    RETURN_UMODE_M umode_test3

umode_test3:
    wfi
    TEST_FAIL

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
```

---

#### Test 1.6: `test_umode_memory_sum.s`
**Purpose**: Verify SUM bit controls S-mode access to U-mode pages

**Test Flow**:
```
1. Setup page table with U-mode page
2. Enter S-mode
3. Attempt to access U-mode page with SUM=0 → page fault
4. Set SUM=1
5. Attempt to access U-mode page with SUM=1 → success
6. Enter U-mode
7. Verify U-mode can still access its own pages
8. SUCCESS
```

**Note**: This test requires MMU/virtual memory support. If MMU is not fully implemented, mark as SKIP or implement simplified version.

**Implementation**:
```assembly
_start:
    TEST_PREAMBLE

    # Setup simple page table (if MMU implemented)
    # Mark a page as U-mode accessible

    # Test 1: S-mode access with SUM=0 (should fault)
    DISABLE_SUM
    ENTER_SMODE_M smode_test1

smode_test1:
    # Attempt to load from U-mode page
    la t0, umode_page
    lw t1, 0(t0)        # Should cause page fault or access fault
    TEST_FAIL

s_trap_handler:
    # Verify it's a load page fault or access fault
    csrr t0, scause
    li t1, CAUSE_LOAD_PAGE_FAULT
    beq t0, t1, test_sum_enabled
    li t1, CAUSE_LOAD_ACCESS
    beq t0, t1, test_sum_enabled
    j test_fail

test_sum_enabled:
    # Test 2: S-mode access with SUM=1 (should work)
    ENABLE_SUM
    # Set SEPC to try again
    csrw sepc, ...
    sret

smode_test2:
    lw t1, 0(t0)        # Should succeed
    TEST_PASS

m_trap_handler:
    TEST_FAIL

test_fail:
    TEST_FAIL

.section .data
umode_page:
    .word 0x12345678

TRAP_TEST_DATA_AREA
```

---

### Phase 1 Validation

**After implementing all 6 tests**:
```bash
# Run all U-mode tests
make test-custom-all | grep umode

# Expected output:
# ✓ test_umode_entry_from_mmode
# ✓ test_umode_entry_from_smode
# ✓ test_umode_ecall
# ✓ test_umode_csr_violation
# ✓ test_umode_illegal_instr
# ✓ test_umode_memory_sum (or SKIP if MMU incomplete)
```

**Success Criteria**:
- All 6 tests compile without errors
- At least 5/6 tests pass (1 may SKIP if MMU incomplete)
- No regressions in existing tests (`make test-quick` still passes)

---

## 📋 PHASE 2: Status Register State Machine (5 tests)

**Priority**: 🟠 HIGH
**Estimated Time**: 1-2 hours
**Goal**: Verify mstatus/sstatus state transitions are correct

### Why This Matters
The privilege mode state machine (xIE, xPIE, xPP) is critical for correct trap handling and returns. Bugs here can cause privilege escalation or incorrect interrupt handling.

### State Machine Rules to Test

**MRET Behavior**:
```
1. Restore interrupt enable: MIE ← MPIE
2. Set previous interrupt enable: MPIE ← 1
3. Restore privilege: privilege ← MPP
4. Set previous privilege: MPP ← U (or M if U-mode not supported)
5. Jump to MEPC
```

**SRET Behavior**:
```
1. SIE ← SPIE
2. SPIE ← 1
3. privilege ← SPP
4. SPP ← U
5. Jump to SEPC
```

**Trap Entry**:
```
1. Save interrupt enable: xPIE ← xIE
2. Disable interrupts: xIE ← 0
3. Save privilege: xPP ← current_privilege
4. Update privilege: privilege ← M or S (depending on delegation)
5. Save PC: xEPC ← PC
6. Jump to xTVEC
```

### Tests to Implement

#### Test 2.1: `test_mstatus_state_mret.s`
**Purpose**: Verify MRET state transitions

**Test Cases**:
1. MRET with MPIE=0, MIE=1 → After MRET: MIE=0, MPIE=1
2. MRET with MPIE=1, MIE=0 → After MRET: MIE=1, MPIE=1
3. MRET with MPP=S → privilege becomes S
4. MRET with MPP=U → privilege becomes U
5. MRET with MPP=M → privilege stays M

**Implementation Sketch**:
```assembly
_start:
    # Test 1: MIE ← MPIE (MPIE=0)
    li t0, ~MSTATUS_MPIE
    csrrc zero, mstatus, t0    # Clear MPIE
    li t0, MSTATUS_MIE
    csrrs zero, mstatus, t0    # Set MIE

    la t0, after_mret1
    csrw mepc, t0
    mret

after_mret1:
    # Verify MIE is now 0
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail
    # Verify MPIE is now 1
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Continue with more test cases...
    TEST_PASS
```

---

#### Test 2.2: `test_mstatus_state_sret.s`
**Purpose**: Verify SRET state transitions

**Similar to 2.1 but for S-mode**

---

#### Test 2.3: `test_mstatus_state_trap.s`
**Purpose**: Verify trap entry state updates

**Test Cases**:
1. Trap from M-mode: MPIE ← MIE, MIE ← 0, MPP ← M
2. Trap from S-mode: MPIE ← MIE, MIE ← 0, MPP ← S
3. Trap from U-mode: MPIE ← MIE, MIE ← 0, MPP ← U
4. Delegated trap to S-mode: SPIE ← SIE, SIE ← 0, SPP ← current

**Implementation Sketch**:
```assembly
_start:
    # Test 1: Trap from M-mode
    ENABLE_MIE

    # Trigger exception
    ecall

m_trap_handler:
    # Verify MIE is now 0
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail
    # Verify MPIE is now 1 (was MIE before trap)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail
    # Verify MPP is M
    EXPECT_MPP PRIV_M, test_fail

    # Test 2: Trap from S-mode
    ENTER_SMODE_M smode_code
    # ... continue testing
```

---

#### Test 2.4: `test_mstatus_nested_traps.s`
**Purpose**: Verify state preserved across nested traps

**Test Flow**:
```
1. M-mode: Set MIE=1, MPIE=0, MPP=S
2. Enter S-mode via MRET
3. In S-mode: Trigger trap (goes back to M)
4. In M-trap handler: Verify state saved correctly
5. Modify state and return
6. Verify state restored correctly
```

**This tests that nested traps don't corrupt state**

---

#### Test 2.5: `test_mstatus_interrupt_enables.s`
**Purpose**: Verify MIE/SIE bits actually control interrupt delivery

**Test Cases**:
1. MIE=0: Machine interrupts disabled (even if pending)
2. MIE=1: Machine interrupts enabled (if pending)
3. SIE=0: Supervisor interrupts disabled in S-mode
4. SIE=1: Supervisor interrupts enabled in S-mode
5. Privilege interaction: S-mode can't disable M-mode interrupts via SIE

**Note**: This test requires interrupt generation capability. May need timer or software interrupt support.

---

### Phase 2 Validation

```bash
# Run all status state tests
make test-custom-all | grep mstatus_state

# Expected: All 5 tests pass
```

---

## 📋 PHASE 3: Interrupt Handling (6 tests)

**Priority**: 🟠 HIGH
**Estimated Time**: 2-3 hours
**Goal**: Test interrupt delegation and handling

**Note**: This phase depends on having interrupt generation capability in the testbench. If not available, these tests may need to be deferred or implemented differently.

### Tests to Implement

#### Test 3.1: `test_interrupt_mtimer.s`
**Purpose**: Verify machine timer interrupt

**Requirements**: Testbench must support timer interrupt injection or MTIP bit manipulation

**Test Flow**:
```
1. Enable machine timer interrupts (mie.MTIE = 1)
2. Set mstatus.MIE = 1
3. Trigger timer interrupt (set mip.MTIP = 1)
4. Verify trap to M-mode with cause = 0x80000007
5. Clear interrupt, verify execution resumes
```

---

#### Test 3.2: `test_interrupt_delegation.s`
**Purpose**: Verify interrupt delegation via mideleg

**Test Flow**:
```
1. Delegate supervisor timer interrupt (mideleg bit 5)
2. Enter S-mode
3. Enable S-mode timer interrupts
4. Trigger timer interrupt
5. Verify trap to S-mode (not M-mode)
6. Clear delegation
7. Trigger again → should go to M-mode
```

---

#### Test 3.3: `test_interrupt_priority.s`
**Purpose**: Verify interrupt vs exception priority

**Per RISC-V spec**:
- Interrupts are prioritized over exceptions at the same instruction
- M-mode interrupts > S-mode interrupts

**Test Cases**:
1. Interrupt pending + exception in same instruction → interrupt taken first
2. Multiple interrupts pending → highest priority taken
3. MEI > MSI > MTI > SEI > SSI > STI (interrupt priority order)

---

#### Test 3.4: `test_interrupt_pending.s`
**Purpose**: Verify mip/sip pending bit behavior

**Test Cases**:
1. Software interrupt: Write mip.MSIP, verify readable
2. Timer interrupt: External source sets MTIP
3. S-mode view: sip shows subset of mip
4. Read-only bits: External interrupts can't be set by software

---

#### Test 3.5: `test_interrupt_masking.s`
**Purpose**: Verify mie/sie masking

**Test Cases**:
1. mie.MTIE = 0 → timer interrupt pending but not taken
2. mie.MTIE = 1 → timer interrupt taken
3. sie.STIE controls S-mode timer interrupt delivery
4. Delegation + masking interaction

---

#### Test 3.6: `test_interrupt_nested.s`
**Purpose**: Verify nested interrupt handling

**Test Flow**:
```
1. Take interrupt in M-mode
2. In handler: Re-enable MIE
3. Trigger another interrupt
4. Verify both handled correctly
5. Verify return addresses preserved
```

---

### Phase 3 Validation

**If interrupt support available**:
```bash
make test-custom-all | grep interrupt
# Expected: 6/6 tests pass
```

**If interrupt support NOT available**:
- Mark tests as TODO
- Implement when interrupt generation capability added
- Can manually test by modifying mip bits if allowed

---

## 📋 PHASE 4: Exception Coverage (8 tests)

**Priority**: 🟡 MEDIUM
**Estimated Time**: 2-3 hours
**Goal**: Test all exception cause codes

### Exception Cause Codes to Cover

| Code | Exception | Currently Tested? |
|------|-----------|-------------------|
| 0 | Instruction address misaligned | ❌ |
| 1 | Instruction access fault | ❌ |
| 2 | Illegal instruction | ✅ |
| 3 | Breakpoint | ❌ |
| 4 | Load address misaligned | ❌ |
| 5 | Load access fault | ❌ |
| 6 | Store/AMO address misaligned | ❌ |
| 7 | Store/AMO access fault | ❌ |
| 8 | ECALL from U-mode | ✅ (Phase 1) |
| 9 | ECALL from S-mode | ✅ |
| 11 | ECALL from M-mode | ❌ |
| 12 | Instruction page fault | ❌ |
| 13 | Load page fault | ❌ |
| 15 | Store/AMO page fault | ❌ |

### Tests to Implement

#### Test 4.1: `test_exception_breakpoint.s`
**Purpose**: EBREAK instruction (cause 3)

```assembly
_start:
    TEST_PREAMBLE

    ebreak              # Should trap

m_trap_handler:
    EXPECT_CSR mcause, CAUSE_BREAKPOINT, test_fail
    # Verify MEPC points to EBREAK
    csrr t0, mepc
    la t1, _start
    addi t1, t1, 4      # Offset to ebreak
    beq t0, t1, test_pass
    j test_fail

test_pass:
    TEST_PASS
```

---

#### Test 4.2: `test_exception_all_ecalls.s`
**Purpose**: Test ECALL from all three modes

**Test Flow**:
```
1. ECALL from M-mode → cause 11
2. ECALL from S-mode → cause 9
3. ECALL from U-mode → cause 8
```

---

#### Test 4.3: `test_exception_load_misaligned.s`
**Purpose**: Misaligned load (cause 4)

**Test Cases**:
```
1. LW from address 0x1 (not 4-byte aligned)
2. LH from address 0x1 (not 2-byte aligned)
3. Verify LB from any address works (no alignment requirement)
```

**Note**: If hardware supports misaligned access, this test may not trap!

```assembly
_start:
    TEST_PREAMBLE

    # Attempt misaligned LW
    la t0, data_area
    addi t0, t0, 1      # Make odd address
    lw t1, 0(t0)        # Should trap (or succeed if HW supports)

    # If we reach here, hardware supports misaligned
    TEST_PASS           # Or mark as SKIP

m_trap_handler:
    # Verify cause = 4
    EXPECT_CSR mcause, CAUSE_MISALIGNED_LOAD, test_fail
    TEST_PASS

.section .data
data_area:
    .word 0x12345678
```

---

#### Test 4.4: `test_exception_store_misaligned.s`
**Purpose**: Misaligned store (cause 6)

Similar to 4.3 but for stores.

---

#### Test 4.5: `test_exception_fetch_misaligned.s`
**Purpose**: Misaligned instruction fetch (cause 0)

**Test Flow**:
```
1. Set MEPC to odd address (not 2-byte aligned if C-ext, or not 4-byte if no C-ext)
2. Execute MRET
3. Should trap with cause = 0
```

**Note**: With C extension, 2-byte alignment is OK. Without C extension, must be 4-byte aligned.

---

#### Test 4.6: `test_exception_page_fault.s`
**Purpose**: Page faults (causes 12, 13, 15)

**Requires**: MMU/virtual memory support

**Test Cases**:
1. Fetch from invalid page → cause 12
2. Load from invalid page → cause 13
3. Store to invalid page → cause 15
4. Access to page with wrong permissions

**If MMU not fully implemented**: Mark as SKIP or TODO

---

#### Test 4.7: `test_exception_priority.s`
**Purpose**: Exception priority when multiple occur

**Per RISC-V spec, priority order** (highest to lowest):
1. Instruction address misaligned
2. Instruction access fault
3. Illegal instruction
4. Breakpoint
5. Load/store address misaligned
6. Load/store access fault
7. Environment call
8. Instruction/load/store page fault

**Test Flow**: Trigger multiple exceptions in one instruction (tricky!) or verify precedence rules.

---

#### Test 4.8: `test_exception_delegation_full.s`
**Purpose**: Test delegation for all delegatable exceptions

**Delegatable exceptions** (can go to S-mode):
- All synchronous exceptions except M-mode ECALL (cause 11)

**Test Flow**:
```
1. Delegate all exceptions via medeleg = 0xFFFF
2. Enter S-mode
3. Trigger each exception type
4. Verify each goes to S-mode handler (not M-mode)
5. Clear delegation
6. Trigger again → should go to M-mode
```

---

### Phase 4 Validation

```bash
make test-custom-all | grep exception
# Expected: Most tests pass
# Some may SKIP if MMU not implemented
# Some may PASS with note if HW supports misaligned access
```

---

## 📋 PHASE 5: CSR Edge Cases (4 tests)

**Priority**: 🟡 MEDIUM
**Estimated Time**: 1-2 hours
**Goal**: Verify CSR field constraints and side effects

### Tests to Implement

#### Test 5.1: `test_csr_readonly_verify.s`
**Purpose**: Verify read-only CSRs are immutable

**Read-only CSRs**:
- mvendorid (0xF11)
- marchid (0xF12)
- mimpid (0xF13)
- mhartid (0xF14)
- misa (0x301) - may be read-only or partially writable

**Test Flow**:
```
1. Read initial value of each CSR
2. Attempt to write different value
3. Read again
4. Verify value unchanged
```

```assembly
_start:
    # Test mvendorid
    csrr t0, mvendorid
    li t1, 0xFFFFFFFF
    csrw mvendorid, t1      # Attempt write
    csrr t2, mvendorid
    bne t0, t2, test_fail   # Should be unchanged

    # Repeat for other read-only CSRs
    TEST_PASS
```

---

#### Test 5.2: `test_csr_sstatus_masking.s`
**Purpose**: Verify sstatus is proper subset of mstatus

**Rules**:
- Writing sstatus only affects S-mode visible fields
- M-mode fields (MPP, MPIE) not writable via sstatus
- Reading sstatus shows only S-mode fields

**Test Flow**:
```
1. Write mstatus with known pattern
2. Read sstatus
3. Verify M-mode fields are masked to 0
4. Write sstatus with different pattern
5. Read mstatus
6. Verify M-mode fields unchanged
```

---

#### Test 5.3: `test_csr_warl_fields.s`
**Purpose**: Verify WARL (Write Any, Read Legal) field constraints

**WARL Fields to Test**:

1. **mstatus.MPP**: Can only be 00 (U), 01 (S), or 11 (M)
   - Writing 10 should read back as legal value

2. **mstatus.SPP**: Only 1 bit (0=U, 1=S)
   - Can't store M-mode value

3. **xTVEC mode bits [1:0]**:
   - 00 = Direct mode (all traps to BASE)
   - 01 = Vectored mode (interrupts to BASE + 4×cause)
   - 10, 11 = Reserved
   - Writing 10 or 11 should read back as legal value

4. **xTVEC.BASE alignment**:
   - Must be aligned to 4 bytes (Direct) or more (Vectored)
   - Lower bits read as 0

**Implementation Example**:
```assembly
_start:
    # Test MPP invalid value
    csrr t0, mstatus
    li t1, 0xFFFFFFFF
    csrw mstatus, t1
    csrr t2, mstatus

    # Extract MPP field
    li t3, MSTATUS_MPP_MASK
    and t4, t2, t3
    srli t4, t4, MSTATUS_MPP_SHIFT

    # Verify MPP is legal (0, 1, or 3, not 2)
    li t5, 2
    beq t4, t5, test_fail   # MPP should not be 2

    # Continue testing other WARL fields
    TEST_PASS
```

---

#### Test 5.4: `test_csr_side_effects.s`
**Purpose**: Verify CSR write side effects

**Side Effects to Test**:

1. **Writing mstatus affects sstatus** (they're views of same register)
2. **Writing SATP flushes TLB** (if MMU implemented)
3. **Writing mie affects sie** (sie is subset)
4. **Writing mip affects sip** (sip is subset)

**Test Flow**:
```
1. Write mstatus, verify sstatus reflects change
2. Write sstatus, verify mstatus reflects change (for visible fields)
3. Write mie, verify sie updated
4. etc.
```

---

### Phase 5 Validation

```bash
make test-custom-all | grep csr
# Expected: All 4 tests pass
```

---

## 📋 PHASE 6: Delegation Edge Cases (3 tests)

**Priority**: 🟢 LOW
**Estimated Time**: 1 hour
**Goal**: Test unusual delegation scenarios

### Tests to Implement

#### Test 6.1: `test_delegation_to_current_mode.s`
**Purpose**: What happens when exception delegates to current mode?

**Scenario**:
```
1. Running in S-mode
2. Illegal instruction exception
3. medeleg[2] = 1 (delegate to S-mode)
4. Already in S-mode → what happens?
```

**Expected Behavior** (per spec):
- Exception still goes to S-mode handler
- SEPC updated
- SPP preserves current privilege (S)

---

#### Test 6.2: `test_delegation_priority.s`
**Purpose**: Multiple exceptions with different delegation

**Scenario**:
```
1. Configure medeleg to delegate some exceptions to S, not others
2. Trigger instruction that could cause multiple exceptions
3. Verify correct handler invoked based on priority + delegation
```

---

#### Test 6.3: `test_delegation_disable.s`
**Purpose**: Verify clearing delegation works

**Test Flow**:
```
1. Delegate exception to S-mode
2. Trigger exception → goes to S-mode
3. Clear delegation (medeleg[bit] = 0)
4. Trigger same exception → goes to M-mode
5. Verify state handled correctly
```

---

### Phase 6 Validation

```bash
make test-custom-all | grep delegation
# Expected: All 3 tests pass
```

---

## 📋 PHASE 7: Stress & Regression (2 tests)

**Priority**: 🟢 LOW
**Estimated Time**: 1 hour
**Goal**: Catch edge cases and regressions

### Tests to Implement

#### Test 7.1: `test_priv_rapid_switching.s`
**Purpose**: Rapidly switch between privilege modes

**Test Flow**:
```
1. M → S → M → S → M (via MRET/ECALL)
2. M → S → U → S → M (via MRET/SRET/ECALL)
3. Verify state preserved correctly through all transitions
4. Run 100+ transitions
```

**This catches state corruption bugs**

---

#### Test 7.2: `test_priv_comprehensive.s`
**Purpose**: All-in-one regression test

**Test Flow**:
```
1. Test basic privilege transitions
2. Test CSR access from each mode
3. Test delegation
4. Test state machine
5. Test exceptions from each mode
6. Verify all major features work together
```

**This is a comprehensive regression test to run before each release**

---

## Test Template & Patterns

### Standard Test Template

```assembly
# ==============================================================================
# Test: [Test Name]
# ==============================================================================
#
# Purpose: [What this test verifies]
#
# Test Flow:
#   1. [Step 1]
#   2. [Step 2]
#   ...
#
# Expected Result: [What should happen]
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE           # Setup trap handlers, clear delegations

    ###########################################################################
    # TEST BODY
    ###########################################################################
    # [Your test code here]

    TEST_PASS               # Mark success

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # [M-mode trap handling]
    TEST_FAIL               # Or appropriate handling

s_trap_handler:
    # [S-mode trap handling]
    TEST_FAIL               # Or appropriate handling

# =============================================================================
# FAILURE HANDLER
# =============================================================================
test_fail:
    TEST_FAIL

# =============================================================================
# DATA SECTION
# =============================================================================
TRAP_TEST_DATA_AREA

.align 4
```

### Common Patterns

**Pattern 1: Multi-stage test**
```assembly
_start:
    li s0, 0                # Stage counter

stage1:
    # Test something
    addi s0, s0, 1
    # Trigger event

m_trap_handler:
    li t0, 1
    beq s0, t0, stage2_handler
    li t0, 2
    beq s0, t0, stage3_handler
    # etc.
```

**Pattern 2: Test with delegation**
```assembly
_start:
    # Test 1: Without delegation
    CLEAR_EXCEPTION_DELEGATION
    # Trigger exception

    # Test 2: With delegation
    DELEGATE_EXCEPTION [CAUSE]
    # Trigger same exception
```

**Pattern 3: CSR comparison**
```assembly
    # Save initial value
    csrr s0, [csr]

    # Modify
    li t0, [value]
    csrw [csr], t0

    # Verify
    csrr t1, [csr]
    bne t0, t1, test_fail

    # Restore
    csrw [csr], s0
```

---

## Validation Strategy

### Per-Test Validation

After implementing each test:

```bash
# 1. Assemble and check for errors
tools/assemble.sh tests/asm/[test_name].s

# 2. Examine generated code
riscv64-unknown-elf-objdump -d tests/vectors/[test_name].elf | less

# 3. Run test
tools/run_test.sh [test_name]

# 4. Check result
# Expected: ✓ Test PASSED
```

### Per-Phase Validation

After completing each phase:

```bash
# 1. Run quick regression (ensure no regressions)
make test-quick

# 2. Run all tests in phase
make test-custom-all | grep [phase_pattern]

# 3. Update test catalog
make catalog

# 4. Review catalog for new tests
cat docs/TEST_CATALOG.md
```

### Full Suite Validation

After all phases complete:

```bash
# 1. Run all custom tests
make test-custom-all

# 2. Run official compliance tests
env XLEN=32 ./tools/run_official_tests.sh all

# 3. Generate statistics
# Count: Total tests, passed, failed
# Coverage: Privilege modes, exception causes, CSRs

# 4. Update documentation
# - CLAUDE.md: Update test statistics
# - TEST_CATALOG.md: Should show all 34 new tests
# - README.md: Update compliance information
```

---

## Success Criteria

### Phase-Level Success

Each phase is successful when:
- ✅ All tests in phase compile without errors
- ✅ At least 90% of tests pass (some may SKIP if features not implemented)
- ✅ No regressions in `make test-quick`
- ✅ Tests are documented in TEST_CATALOG.md

### Overall Success

The complete implementation is successful when:
- ✅ 32+ of 34 tests pass (allowing 2 SKIP for optional features)
- ✅ All 81 official compliance tests still pass
- ✅ `make test-quick` passes (no regressions)
- ✅ All privilege modes (M/S/U) tested
- ✅ All exception causes covered
- ✅ State machine verified
- ✅ Documentation updated

### Stretch Goals

- 🎯 100% test pass rate (34/34)
- 🎯 All MMU/page fault tests working (not SKIP)
- 🎯 All interrupt tests working (not SKIP/TODO)
- 🎯 Formal verification of critical paths
- 🎯 Performance benchmarks for privilege switches

---

## Session Planning

### Recommended Session Breakdown

**Session 1: Phase 1 (2-3 hours)**
- Goal: Complete all 6 U-mode tests
- Tasks:
  1. Review macro library (15 min)
  2. Implement tests 1.1-1.3 (60 min)
  3. Implement tests 1.4-1.6 (60 min)
  4. Run and debug (30 min)
  5. Validate phase (15 min)

**Session 2: Phase 2 (1.5-2 hours)**
- Goal: Complete all 5 state machine tests
- Tasks similar structure

**Session 3: Phase 3 (2-3 hours)**
- Goal: Complete interrupt tests (or defer if HW support missing)
- Tasks similar structure

**Session 4: Phase 4 (2-3 hours)**
- Goal: Complete exception coverage tests
- Tasks similar structure

**Session 5: Phases 5-7 (2-3 hours)**
- Goal: Complete remaining tests, validation, documentation
- Tasks:
  1. Implement Phase 5 (60 min)
  2. Implement Phase 6 (30 min)
  3. Implement Phase 7 (30 min)
  4. Full validation (30 min)
  5. Update all docs (30 min)

### Inter-Session Checklist

**Before each session**:
- [ ] Review previous session's tests
- [ ] Run `make test-quick` to ensure no regressions
- [ ] Review relevant RISC-V spec sections
- [ ] Check macro library documentation

**After each session**:
- [ ] Commit all new tests with descriptive messages
- [ ] Update TEST_CATALOG.md
- [ ] Document any RTL bugs found
- [ ] Note any tests that need to be SKIPPED
- [ ] Update phase completion status

### Daily Checklist Template

```markdown
## Session [N]: [Phase Name]

**Date**: [Date]
**Duration**: [Start] - [End]
**Goal**: [Phase goal]

### Tests Implemented
- [ ] test_name_1.s - STATUS
- [ ] test_name_2.s - STATUS
- [ ] test_name_3.s - STATUS

### Issues Found
- Issue 1: [Description]
- Issue 2: [Description]

### Tests Passing
- Phase N: X/Y
- Quick regression: PASS/FAIL
- Official tests: PASS/FAIL

### Next Session
- [ ] Task 1
- [ ] Task 2
- [ ] Task 3

### Notes
- [Any important observations]
```

---

## Debugging Guide

### Common Issues

**Issue 1: Test times out**
- **Symptom**: Simulation reaches timeout, no ebreak
- **Causes**:
  - Infinite loop
  - PC stuck
  - Waiting for interrupt that never comes
- **Debug**:
  ```bash
  # Check final PC
  # Check what instruction is at that PC
  riscv64-unknown-elf-objdump -d tests/vectors/[test].elf | grep [PC]

  # Add debug output if testbench supports it
  ```

**Issue 2: Test fails with wrong cause code**
- **Symptom**: mcause/scause has unexpected value
- **Debug**:
  - Check RTL exception priority logic
  - Verify instruction actually triggers expected exception
  - Check if delegation is interfering

**Issue 3: Privilege transitions don't work**
- **Symptom**: After MRET/SRET, still in wrong mode
- **Debug**:
  - Verify MPP/SPP bits are set correctly before xRET
  - Check RTL privilege mode update logic
  - Verify current_priv signal in RTL

**Issue 4: CSR access doesn't trap when it should**
- **Symptom**: U-mode can access privileged CSR
- **Debug**:
  - Check CSR privilege checking logic in RTL
  - Verify csr_priv_ok signal
  - Check current_priv value

### Debug Instrumentation

**Add to tests for debugging**:
```assembly
# Save important state before critical operations
SAVE_ALL_CSRS debug_area

# Mark progress
TEST_STAGE N    # Sets x29 = N

# Breadcrumb trail
li t6, 0xBEEF0001    # Before operation 1
li t6, 0xBEEF0002    # Before operation 2
# etc.
```

**Check in waveform viewer** (if available):
- current_priv signal
- csr_priv_ok signal
- trap_entry signal
- PC value
- Instruction being executed

---

## Documentation Updates

### Files to Update After Completion

**1. CLAUDE.md**
- Update "Total Implementation Statistics"
- Update "Custom Tests" count
- Add new section on privilege testing if needed

**2. TEST_CATALOG.md**
- Will be auto-updated by `make catalog`
- Verify all 34 new tests appear
- Check categorization is correct

**3. README.md**
- Update test statistics
- Mention privilege mode test suite
- Update any relevant sections

**4. PHASES.md** (if exists)
- Mark privilege testing phase as complete
- Update status

**5. ARCHITECTURE.md** (if exists)
- Document any RTL changes made to fix bugs
- Update privilege mode handling documentation

### New Documentation to Create

**1. PRIVILEGE_TESTING_RESULTS.md**
```markdown
# Privilege Mode Testing - Results

## Summary
- Tests Implemented: 34
- Tests Passing: XX
- Tests Skipped: YY
- Coverage: [Details]

## Bugs Found and Fixed
1. [Bug description and fix]
2. [Bug description and fix]

## Known Limitations
1. [Limitation]
2. [Limitation]

## Future Work
1. [Enhancement]
2. [Enhancement]
```

---

## Risk Mitigation

### Potential Risks

**Risk 1: RTL bugs block progress**
- **Mitigation**: Document bugs, create workaround tests, continue with other tests
- **Escalation**: If critical bug blocks many tests, fix RTL first

**Risk 2: Feature not implemented (e.g., interrupts, MMU)**
- **Mitigation**: Mark tests as SKIP/TODO, implement when feature available
- **Acceptance**: Some tests may remain SKIP in initial release

**Risk 3: Spec ambiguity**
- **Mitigation**: Document interpretation, reference spec section, ask for clarification if needed
- **Resolution**: Follow most conservative interpretation

**Risk 4: Time overrun**
- **Mitigation**: Prioritize high-value tests (Phases 1-2), defer low-priority
- **Adjustment**: Can reduce Phase 3 scope if interrupt support missing

### Fallback Plan

If full implementation not feasible:

**Minimum Viable Test Suite** (12 tests):
- Phase 1: All 6 U-mode tests (CRITICAL)
- Phase 2: Tests 2.1, 2.2, 2.3 (state machine)
- Phase 4: Tests 4.1, 4.2, 4.3 (exception coverage)

**Reduced Timeline**: ~5-6 hours

---

## Appendix

### Reference Links

- **RISC-V Privileged Spec v1.12**: https://riscv.org/technical/specifications/
- **RISC-V Compliance Tests**: https://github.com/riscv/riscv-compliance
- **Project Macro Library**: `tests/asm/include/README.md`
- **Gap Analysis**: `docs/PRIVILEGE_TEST_ANALYSIS.md`

### Quick Command Reference

```bash
# Build single test
tools/assemble.sh tests/asm/[test].s

# Run single test
tools/run_test.sh [test_name]

# Run quick regression (14 tests, 7 seconds)
make test-quick

# Run all custom tests
make test-custom-all

# Run official tests (81 tests, ~80 seconds)
env XLEN=32 ./tools/run_official_tests.sh all

# Update test catalog
make catalog

# Check hex files exist
make check-hex

# Rebuild all hex files
make rebuild-hex

# View test catalog
cat docs/TEST_CATALOG.md

# View macro reference
cat tests/asm/include/README.md
```

### Macro Quick Reference

See `tests/asm/include/README.md` for full reference.

**Most Used Macros**:
```assembly
TEST_PREAMBLE                   # Setup
ENTER_SMODE_M target            # M→S
ENTER_UMODE_M target            # M→U
ENTER_UMODE_S target            # S→U
EXPECT_CSR csr, val, fail       # Verify
TEST_PASS                       # Success
TEST_FAIL                       # Failure
DELEGATE_EXCEPTION cause        # Delegate
```

---

## Conclusion

This implementation plan provides a comprehensive roadmap for creating 34 privilege mode tests across 7 phases. The plan is designed to be:

- **Structured**: Clear phases with dependencies
- **Flexible**: Can skip phases if features not implemented
- **Validated**: Success criteria at each level
- **Documented**: Templates and patterns provided
- **Realistic**: Time estimates based on complexity

**Total Estimated Time**: 10-15 hours
**Minimum Viable**: 5-6 hours (12 critical tests)
**Success Rate Target**: 90%+ (32+ of 34 tests passing)

The macro library eliminates ~88% of boilerplate code, making implementation significantly faster than manual assembly. The structured approach ensures comprehensive coverage of privilege mode functionality.

**Ready to begin with Phase 1 in next session!**

---

**Document Version**: 1.0
**Last Updated**: 2025-10-23
**Next Review**: After Phase 1 completion
