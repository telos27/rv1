# test_interrupt_mie_masking.s - Test mstatus.MIE masking in M-mode
# Tests that interrupts don't fire when MIE=0, fire when MIE=1
# Author: RV1 Project - Phase 1.5 Interrupt Completion
# Date: 2025-10-27

.include "tests/asm/include/priv_test_macros.s"

.section .text
.global _start

_start:
    # Initialize test
    li      sp, 0x80010000

    # Set up trap handler
    SET_MTVEC_DIRECT m_trap_handler

    # Enable timer interrupt in mie
    li      t0, 0x80                # MTIE
    csrs    mie, t0

    # Set timer to fire immediately
    li      t0, 0x02004000          # MTIMECMP address
    li      t1, 100
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    # Wait for MTIP to be set in mip
    li      t1, 1000
1:
    csrr    t0, mip
    andi    t0, t0, 0x80            # Check MTIP
    bnez    t0, mtip_set
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail

mtip_set:
    # MTIP is set, but MIE=0, so interrupt should NOT fire

    # Clear interrupt count
    la      t0, int_count
    sw      zero, 0(t0)

    # Busy loop with MIE=0 - interrupt should not fire
    li      t1, 500
1:
    addi    t1, t1, -1
    bnez    t1, 1b

    # Verify interrupt did NOT fire
    la      t0, int_count
    lw      t1, 0(t0)
    bnez    t1, test_fail           # FAIL: Interrupt fired with MIE=0

    # Now enable MIE - interrupt should fire immediately
    li      t0, 0x08                # MIE bit
    csrs    mstatus, t0

    # Wait for interrupt
    li      t1, 1000
1:
    la      t0, int_count
    lw      t2, 0(t0)
    bnez    t2, got_interrupt
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail               # FAIL: Interrupt didn't fire with MIE=1

got_interrupt:
    # Verify it was MTI
    la      t0, cause
    lw      t1, 0(t0)
    li      t2, 0x80000007          # MTI cause
    bne     t1, t2, test_fail

    # Success
    li      a0, 0
    ebreak

test_fail:
    li      a0, 1
    ebreak

# ==============================================================================
# M-mode Trap Handler
# ==============================================================================
.align 4
m_trap_handler:
    # Save cause
    csrr    t0, mcause
    la      t1, cause
    sw      t0, 0(t1)

    # Increment count
    la      t0, int_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    # Clear timer
    li      t0, 0x02004000
    li      t1, 1000000
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    mret

# ==============================================================================
# Data Section
# ==============================================================================
.section .data
.align 4
int_count:      .word 0
cause:          .word 0
