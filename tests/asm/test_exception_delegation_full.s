# ==============================================================================
# Test: test_exception_delegation_full.s
# ==============================================================================
#
# Purpose: Test exception delegation via medeleg CSR
#
# Test Flow:
#   Stage 1: Breakpoint from S-mode, no delegation (goes to M-mode)
#   Stage 2: Breakpoint from S-mode, with delegation (goes to S-mode)
#   Stage 3: Illegal instruction from M-mode never delegates
#
# Coverage:
#   - medeleg CSR functionality
#   - Delegation to S-mode when medeleg[cause]=1
#   - Non-delegation when medeleg[cause]=0
#   - M-mode exceptions never delegate
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE

    ###########################################################################
    # STAGE 1: Breakpoint from S-mode without delegation
    ###########################################################################
    li t0, 1
    csrw mscratch, t0       # Stage marker

    # Clear delegation
    csrw medeleg, zero

    # Enter S-mode
    ENTER_SMODE_M 1f

1:  # In S-mode
    ebreak                  # Should trap to M-mode (no delegation)

    # Unreachable
    TEST_FAIL

    ###########################################################################
    # STAGE 2: Breakpoint from S-mode with delegation
    ###########################################################################
2:  # M-mode handler returns here

    li t0, 2
    csrw sscratch, t0       # Stage marker for S-mode handler

    # Enable delegation of breakpoint (cause=3)
    li t1, (1 << 3)
    csrw medeleg, t1

    # Enter S-mode
    ENTER_SMODE_M 3f

3:  # In S-mode
    ebreak                  # Should trap to S-mode (delegated)

    # S-mode handler will verify and return here
    csrr t0, sscratch
    li t1, 0x0000D303       # DELEG + cause 3
    bne t0, t1, test_fail

    # Return to M-mode
    RETURN_MMODE 4f

    ###########################################################################
    # STAGE 3: Illegal instruction from M-mode never delegates
    ###########################################################################
4:  # In M-mode

    li t0, 3
    csrw mscratch, t0       # Stage marker

    # Try to enable delegation of illegal instruction
    li t1, (1 << 2)
    csrw medeleg, t1

    # Execute illegal instruction from M-mode
    .word 0x00000000        # Should trap to M-mode (not S-mode)

    # M-mode handler will verify and jump to test_pass
    TEST_FAIL

    ###########################################################################
    # Test Success/Fail
    ###########################################################################
test_pass:
    TEST_PASS

test_fail:
    TEST_FAIL

    ###########################################################################
    # M-mode Trap Handler
    ###########################################################################
.align 2
m_trap_handler:
    csrr t0, mcause
    csrr t1, mscratch

    # Stage 1: Breakpoint from S-mode (no delegation)
    li t2, 1
    beq t1, t2, m_stage1

    # Stage 3: Illegal instruction from M-mode
    li t2, 3
    beq t1, t2, m_stage3

    # Unknown
    j test_fail

m_stage1:
    # Verify cause = 3 (breakpoint)
    li t1, 3
    bne t0, t1, test_fail

    # Return to M-mode stage 2
    la t0, 2b
    csrw mepc, t0
    li t0, 0x1800           # MPP = M-mode
    csrw mstatus, t0
    mret

m_stage3:
    # Verify cause = 2 (illegal instruction)
    li t1, 2
    bne t0, t1, test_fail

    # Test passed!
    j test_pass

    ###########################################################################
    # S-mode Trap Handler
    ###########################################################################
.align 2
s_trap_handler:
    csrr t0, scause
    csrr t1, sscratch

    # Stage 2: Breakpoint (delegated)
    li t2, 2
    bne t1, t2, test_fail

    # Verify cause = 3
    li t1, 3
    bne t0, t1, test_fail

    # Set marker and skip EBREAK
    li t0, 0x0000D303
    csrw sscratch, t0
    csrr t0, sepc
    addi t0, t0, 4
    csrw sepc, t0
    sret
