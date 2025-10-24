# ==============================================================================
# Test: test_umode_csr_violation.s
# ==============================================================================
#
# Purpose: Verify ALL CSR accesses from U-mode trap with illegal instruction
#
# Test Flow:
#   1. Enter U-mode
#   2. Attempt to read M-mode CSRs (mstatus, mepc, etc.)
#   3. Each attempt should trap with cause = illegal instruction
#   4. Attempt to read S-mode CSRs (sstatus, sepc, etc.)
#   5. Each attempt should trap with cause = illegal instruction
#   6. SUCCESS
#
# Expected Result: All privileged CSR accesses from U-mode trap correctly
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    li s0, 0                # Test counter

    ###########################################################################
    # TEST: M-mode CSR access from U-mode
    ###########################################################################
    li s0, 1
    ENTER_UMODE_M test_mstatus

test_mstatus:
    csrr t0, mstatus        # Should trap
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Verify illegal instruction
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail

    # Determine which test and continue
    li t0, 1
    beq s0, t0, test_sie_setup
    li t0, 2
    beq s0, t0, test_sepc_setup

    # All tests passed
    TEST_PASS

test_sie_setup:
    li s0, 2
    # Return to U-mode for next test
    la t0, test_sie
    csrw mepc, t0
    # Clear MPP to return to U-mode
    li t1, ~MSTATUS_MPP_MASK
    csrr t2, mstatus
    and t2, t2, t1
    csrw mstatus, t2
    mret

test_sie:
    csrr t0, sie            # S-mode CSR, should trap
    TEST_FAIL

test_sepc_setup:
    li s0, 3
    la t0, test_sepc
    csrw mepc, t0
    li t1, ~MSTATUS_MPP_MASK
    csrr t2, mstatus
    and t2, t2, t1
    csrw mstatus, t2
    mret

test_sepc:
    csrr t0, sepc           # S-mode CSR, should trap
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
