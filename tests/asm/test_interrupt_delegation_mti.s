# test_interrupt_delegation_mti.s - MTI Delegation to S-mode Test
# Simple test: delegate MTI to S-mode and verify it arrives in S-mode
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

    # Delegate MTI to S-mode via mideleg
    li      t0, 0x80                # Bit 7 = MTI delegation
    csrw    mideleg, t0

    # Enable timer interrupt in sie
    li      t0, 0x20                # STIE (bit 5)
    csrs    sie, t0

    # Transition to S-mode with interrupts enabled
    csrr    t0, mstatus
    li      t1, ~0x1800             # Clear MPP
    and     t0, t0, t1
    li      t1, (1 << 11)           # MPP = S-mode
    or      t0, t0, t1
    li      t1, 0x82                # MPIE=1 (becomes SIE), S PIE=1
    or      t0, t0, t1
    csrw    mstatus, t0

    la      t0, s_mode_code
    csrw    mepc, t0

    # Clear flag
    la      t0, s_int_flag
    sw      zero, 0(t0)

    mret

s_mode_code:
    # Now in S-mode with interrupts enabled

    # Set timer to fire in ~400 cycles
    li      t0, 0x02004000          # MTIMECMP address
    li      t1, 400
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    # Wait for S-mode interrupt
    li      t1, 3000
1:
    la      t0, s_int_flag
    lw      t2, 0(t0)
    bnez    t2, got_interrupt
    addi    t1, t1, -1
    bnez    t1, 1b

    # Timeout
    li      a0, 2
    ebreak

got_interrupt:
    # Verify it was STI (cause 5)
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
# M-mode Trap Handler (should NOT be called for delegated interrupts)
# ==============================================================================
.align 4
m_trap_handler:
    # If we're here, delegation failed - set failure code
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

    # Set flag
    li      t0, 1
    la      t1, s_int_flag
    sw      t0, 0(t1)

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
s_int_flag:     .word 0
s_cause:        .word 0
