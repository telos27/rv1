# ==============================================================================
# Test: test_umode_entry_from_mmode.s
# ==============================================================================
#
# Purpose: Verify M→U mode transition via MRET
#
# Test Flow:
#   1. Start in M-mode
#   2. Set MPP = 00 (U-mode)
#   3. Set MEPC to U-mode target address
#   4. Execute MRET
#   5. Verify execution continues in U-mode
#   6. Attempt CSR access (should trap to M-mode)
#   7. Verify trap cause = illegal instruction
#   8. SUCCESS
#
# Expected Result: U-mode entry works, CSR access properly trapped
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

    # Stage marker for debugging
    li s0, 0                # s0 = test stage counter

    ###########################################################################
    # TEST: Enter U-mode from M-mode
    ###########################################################################

    # Stage 1: Prepare to enter U-mode
    li s0, 1

    # Enter U-mode using macro
    # This sets MPP=00, sets MEPC to target, and executes MRET
    ENTER_UMODE_M umode_code

umode_code:
    # Stage 2: Now in U-mode
    li s0, 2

    # Attempt to access M-mode CSR (mstatus)
    # This should trap to M-mode with illegal instruction exception
    csrr t0, mstatus

    # Should never reach here
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Stage 3: Trapped back to M-mode
    li s0, 3

    # Verify the trap cause is illegal instruction (cause = 2)
    csrr t0, mcause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # Verify MEPC points to the CSR instruction
    csrr t0, mepc
    la t1, umode_code
    addi t1, t1, 8          # Offset to csrr instruction (after li s0, 2)
    bne t0, t1, test_fail

    # SUCCESS - we successfully:
    # 1. Entered U-mode from M-mode
    # 2. Detected we're in U-mode (CSR access trapped)
    # 3. Got correct trap cause
    TEST_PASS

s_trap_handler:
    # Should not trap to S-mode since we didn't delegate
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
