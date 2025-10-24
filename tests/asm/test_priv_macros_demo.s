# ==============================================================================
# Test: Privilege Macro Library Demo
# ==============================================================================
#
# This test demonstrates the usage of the privilege test macro library.
# It performs several privilege-related operations using the macros:
#
# 1. Setup trap handlers (TEST_PREAMBLE)
# 2. Verify M-mode CSR access
# 3. Transition M→S using ENTER_SMODE_M
# 4. Verify S-mode CSR access
# 5. Trigger illegal instruction (access M-CSR from S-mode)
# 6. Verify trap delegation works
# 7. Return to M-mode
#
# This test shows how much cleaner tests are with macros vs manual assembly.
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # STAGE 1: Test Setup
    ###########################################################################
    TEST_STAGE 1

    # Setup trap vectors and clear delegations
    TEST_PREAMBLE

    ###########################################################################
    # STAGE 2: Verify M-mode CSR access
    ###########################################################################
    TEST_STAGE 2

    # Write and read mscratch (M-mode CSR)
    li      t0, 0xAAAA5555
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, test_fail

    ###########################################################################
    # STAGE 3: Configure trap delegation
    ###########################################################################
    TEST_STAGE 3

    # Delegate illegal instruction exceptions to S-mode
    DELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR

    ###########################################################################
    # STAGE 4: Transition to S-mode
    ###########################################################################
    TEST_STAGE 4

    # Enter S-mode using macro (much cleaner than manual!)
    ENTER_SMODE_M s_mode_entry

# =============================================================================
# S-MODE CODE
# =============================================================================
s_mode_entry:
    ###########################################################################
    # STAGE 5: Verify S-mode CSR access
    ###########################################################################
    TEST_STAGE 5

    # Access sscratch (should work in S-mode)
    li      t0, 0x12345678
    csrw    sscratch, t0

    # Verify write succeeded
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    ###########################################################################
    # STAGE 6: Trigger illegal instruction exception
    ###########################################################################
    TEST_STAGE 6

    # Try to access mscratch from S-mode (should trap to S-mode handler)
    csrr    t0, mscratch

    # Should never reach here!
    TEST_FAIL_CODE 6

# =============================================================================
# S-MODE TRAP HANDLER
# =============================================================================
s_trap_handler:
    ###########################################################################
    # STAGE 7: Verify we got the right exception
    ###########################################################################
    TEST_STAGE 7

    # Verify cause is illegal instruction
    EXPECT_CSR scause, CAUSE_ILLEGAL_INSTR, test_fail

    # Verify SEPC points to the faulting instruction
    csrr    t0, sepc
    la      t1, s_mode_entry
    addi    t1, t1, 16      # Approximate offset to csrr mscratch

    ###########################################################################
    # STAGE 8: Return to M-mode via ECALL
    ###########################################################################
    TEST_STAGE 8

    # ECALL from S-mode goes to M-mode (not delegated)
    ecall

    # Should never reach here!
    TEST_FAIL_CODE 8

# =============================================================================
# M-MODE TRAP HANDLER
# =============================================================================
m_trap_handler:
    ###########################################################################
    # STAGE 9: Verify ECALL from S-mode
    ###########################################################################
    TEST_STAGE 9

    # Verify cause is ECALL from S-mode
    EXPECT_CSR mcause, CAUSE_ECALL_S, test_fail

    ###########################################################################
    # SUCCESS!
    ###########################################################################
    TEST_STAGE 10
    TEST_PASS

# =============================================================================
# TEST FAILURE HANDLER
# =============================================================================
test_fail:
    # x29 contains the stage where failure occurred
    TEST_FAIL

# =============================================================================
# DATA SECTION
# =============================================================================
TRAP_TEST_DATA_AREA

.align 4
