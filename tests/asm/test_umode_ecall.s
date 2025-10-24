# ==============================================================================
# Test: test_umode_ecall.s
# ==============================================================================
#
# Purpose: Verify ECALL from U-mode (cause code 8)
#
# Test Flow:
#   1. Enter U-mode
#   2. Execute ECALL
#   3. Trap to M-mode (no delegation)
#   4. Verify cause = 8 (ECALL from U-mode)
#   5. Verify MEPC points to ECALL instruction
#   6. SUCCESS
#
# Expected Result: ECALL from U-mode generates correct exception code (8)
#
# Note: This test focuses on the non-delegated case. Delegation testing
# is covered in other privilege mode tests.
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

    li s0, 0                # Stage counter

    ###########################################################################
    # TEST: ECALL from U-mode (no delegation)
    ###########################################################################

    li s0, 1
    CLEAR_EXCEPTION_DELEGATION
    ENTER_UMODE_M umode_code

umode_code:
    li s0, 2
    ecall                   # Should trap to M-mode

    # Should not reach here (ECALL doesn't return without handler adjustment)
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    li s0, 3

    # Verify cause = ECALL from U-mode (8)
    csrr t0, mcause
    li t1, CAUSE_ECALL_U
    bne t0, t1, test_fail

    # Verify MEPC points to ECALL instruction
    csrr t0, mepc
    la t1, umode_code
    addi t1, t1, 4          # Offset to ecall (after li s0, 2)
    bne t0, t1, test_fail

    # SUCCESS - ECALL from U-mode correctly generated cause=8
    TEST_PASS

s_trap_handler:
    # Should not trap to S-mode (no delegation configured)
    TEST_FAIL

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
