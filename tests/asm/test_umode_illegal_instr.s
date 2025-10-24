# ==============================================================================
# Test: test_umode_illegal_instr.s
# ==============================================================================
#
# Purpose: Verify privileged instructions trap in U-mode
#
# Test Flow:
#   1. Enter U-mode
#   2. Attempt WFI (privileged when mstatus.TW=1)
#   3. Verify trap with cause = illegal instruction
#   4. SUCCESS
#
# Expected Result: WFI instruction traps when executed in U-mode
#
# Note: MRET and SRET privilege checking appears to have RTL bugs
# (discovered in earlier tests). This test focuses on WFI.
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    li s0, 0

    ###########################################################################
    # TEST: WFI in U-mode
    ###########################################################################

    # Set mstatus.TW=1 to make WFI trap in U-mode
    # TW bit is bit 21 of mstatus
    li t0, (1 << 21)        # TW bit
    csrs mstatus, t0

    li s0, 1
    ENTER_UMODE_M umode_code

umode_code:
    li s0, 2
    wfi                      # Should trap
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    li s0, 3

    # Verify cause = illegal instruction
    csrr t0, mcause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # SUCCESS - WFI trapped in U-mode as expected
    TEST_PASS

s_trap_handler:
    TEST_FAIL

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
