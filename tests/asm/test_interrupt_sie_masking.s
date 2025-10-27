# test_interrupt_sie_masking.s - Test mstatus.SIE masking in S-mode
# Tests that interrupts don't fire when SIE=0, fire when SIE=1
# Author: RV1 Project - Phase 1.5 Interrupt Completion
# Date: 2025-10-27

.include "tests/asm/include/priv_test_macros.s"

.section .text
.global _start

_start:
    # Initialize test
    li      sp, 0x80010000

    # Set up trap handlers
    SET_MTVEC_DIRECT m_trap_handler
    SET_STVEC_DIRECT s_trap_handler

    # Delegate MTI to S-mode
    li      t0, 0x80                # MTI delegation
    csrw    mideleg, t0

    # Enable timer interrupt in sie
    li      t0, 0x20                # STIE
    csrs    sie, t0

    # Transition to S-mode with SIE=0
    csrr    t0, mstatus
    li      t1, ~0x1800             # Clear MPP
    and     t0, t0, t1
    li      t1, (1 << 11)           # MPP = S-mode
    or      t0, t0, t1
    # Note: MPIE=0, so SIE will be 0 after mret
    csrw    mstatus, t0

    la      t0, s_mode_code
    csrw    mepc, t0

    # Clear count
    la      t0, s_int_count
    sw      zero, 0(t0)

    mret

s_mode_code:
    # Now in S-mode with SIE=0

    # Set timer to fire immediately
    li      t0, 0x02004000
    li      t1, 50
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    # Wait for STIP to be set
    li      t1, 1000
1:
    csrr    t0, sip
    andi    t0, t0, 0x20            # Check STIP
    bnez    t0, stip_set
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail

stip_set:
    # STIP is set, but SIE=0, so interrupt should NOT fire

    # Busy loop with SIE=0
    li      t1, 500
1:
    addi    t1, t1, -1
    bnez    t1, 1b

    # Verify interrupt did NOT fire
    la      t0, s_int_count
    lw      t1, 0(t0)
    bnez    t1, test_fail           # FAIL: Interrupt fired with SIE=0

    # Now enable SIE - interrupt should fire immediately
    li      t0, 0x02                # SIE bit
    csrs    mstatus, t0

    # Wait for interrupt
    li      t1, 1000
1:
    la      t0, s_int_count
    lw      t2, 0(t0)
    bnez    t2, got_interrupt
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail               # FAIL: Interrupt didn't fire with SIE=1

got_interrupt:
    # Verify it was STI
    la      t0, s_cause
    lw      t1, 0(t0)
    li      t2, 0x80000005          # STI cause
    bne     t1, t2, test_fail

    # Success
    li      a0, 0
    ebreak

test_fail:
    li      a0, 1
    ebreak

# ==============================================================================
# M-mode Trap Handler (should not be called)
# ==============================================================================
.align 4
m_trap_handler:
    li      a0, 3
    ebreak

# ==============================================================================
# S-mode Trap Handler
# ==============================================================================
.align 4
s_trap_handler:
    # Save cause
    csrr    t0, scause
    la      t1, s_cause
    sw      t0, 0(t1)

    # Increment count
    la      t0, s_int_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    # Clear timer
    li      t0, 0x02004000
    li      t1, 1000000
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    sret

# ==============================================================================
# Data Section
# ==============================================================================
.section .data
.align 4
s_int_count:    .word 0
s_cause:        .word 0
