# ==============================================================================
# Test: test_exception_ecall_mmode.s
# ==============================================================================
#
# Purpose: Verify ECALL from M-mode (exception cause code 11)
#
# Test Flow:
#   Stage 1: ECALL from M-mode - verify cause=11, mepc points to ECALL
#   Stage 2: ECALL from M-mode - verify mtval=0
#   Stage 3: ECALL from M-mode - verify can return and continue
#
# Expected Results:
#   - mcause = 11 (ECALL from M-mode)
#   - mepc points to ECALL instruction
#   - mtval should be 0 (no additional info)
#   - Trap handler can modify mepc to skip ECALL and continue execution
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
    li s1, 0                # ECALL counter

    ###########################################################################
    # STAGE 1: ECALL from M-mode - verify cause and mepc
    ###########################################################################
stage1:
    li s0, 1
    CLEAR_EXCEPTION_DELEGATION

    # Save address of ECALL for verification
    la s2, ecall1

ecall1:
    ecall                   # Should trap to M-mode (cause=11)

    # Should not reach here immediately (unless handler advances mepc)
    # If we get here, s1 should be 1 (handler incremented it)
    li t0, 1
    bne s1, t0, test_fail

    ###########################################################################
    # STAGE 2: ECALL from M-mode - verify mtval=0
    ###########################################################################
stage2:
    li s0, 2
    la s2, ecall2

ecall2:
    ecall                   # Should trap to M-mode

    li t0, 2
    bne s1, t0, test_fail

    ###########################################################################
    # STAGE 3: ECALL from M-mode - verify can continue after multiple ECALLs
    ###########################################################################
stage3:
    li s0, 3
    la s2, ecall3

ecall3:
    ecall                   # Should trap to M-mode

    li t0, 3
    bne s1, t0, test_fail

    # SUCCESS - All stages passed
    TEST_PASS

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Verify cause = ECALL from M-mode
    csrr t0, mcause
    li t1, CAUSE_ECALL_M
    bne t0, t1, test_fail

    # Verify mepc points to the expected ECALL instruction
    csrr t0, mepc
    bne t0, s2, test_fail

    # Verify mtval = 0 (ECALL provides no additional info)
    csrr t0, mtval
    bnez t0, test_fail

    # Increment ECALL counter
    addi s1, s1, 1

    # Advance mepc past ECALL to allow execution to continue
    # ECALL can be compressed (c.ecall doesn't exist, so always 4 bytes)
    csrr t0, mepc
    addi t0, t0, 4          # ECALL is always uncompressed (0x00000073)
    csrw mepc, t0

    # Return from trap
    mret

s_trap_handler:
    # Should not trap to S-mode (ECALL from M-mode never delegates)
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
