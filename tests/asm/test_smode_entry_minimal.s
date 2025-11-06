# ==============================================================================
# Test: Minimal S-mode Entry Test
# ==============================================================================
#
# This test verifies basic M-mode to S-mode transition via MRET.
# It's a minimal test to debug privilege mode switching.
#
# Test flow:
# 1. Start in M-mode (stage 1)
# 2. Set up MRET to enter S-mode (stage 2)
# 3. Execute MRET
# 4. Execute in S-mode (stage 3)
# 5. Pass
#
# ==============================================================================

.option norvc  # Disable compressed instructions for clarity

.section .text
.globl _start

_start:
    # Stage 1: M-mode initialization
    li      x29, 1

    # Verify we're in M-mode by reading mstatus
    csrr    t0, mstatus

    # Stage 2: Set up S-mode entry
    li      x29, 2

    # Set mepc to S-mode entry point
    la      t0, smode_entry
    csrw    mepc, t0

    # Set MPP to S-mode (01)
    # Clear MPP bits first
    li      t1, 0xFFFFE7FF    # ~0x1800
    csrr    t2, mstatus
    and     t2, t2, t1         # Clear MPP
    li      t1, 0x00000800     # MPP = 01 (S-mode)
    or      t2, t2, t1
    csrw    mstatus, t2

    # Verify MPP is set correctly
    csrr    t3, mstatus
    li      t4, 0x00001800
    and     t3, t3, t4
    li      t4, 0x00000800     # Expected: MPP = 01
    bne     t3, t4, test_fail

    # Execute MRET to enter S-mode
    mret

smode_entry:
    # Stage 3: Now in S-mode
    li      x29, 3

    # Try to read sstatus (should work in S-mode)
    csrr    t0, sstatus

    # Try to read mstatus (should cause illegal instruction in S-mode)
    # But we'll skip this for now to keep test simple

    # Stage 4: Success
    li      x29, 4
    j       test_pass

test_pass:
    # Test passed
    li      t0, 0xDEADBEEF
    mv      x28, t0
    ebreak

test_fail:
    # Test failed
    # x29 contains the stage where we failed
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

.section .data
