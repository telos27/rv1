# test_interrupt_msi_priority.s - MSI > MTI Priority Test
# Tests that MSI (cause 3) has higher priority than MTI (cause 7)
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

    # Set both MSIP and MTIP simultaneously
    li      t0, 0x02000000          # MSIP address
    li      t1, 1
    sw      t1, 0(t0)

    li      t0, 0x02004000          # MTIMECMP address
    sw      zero, 0(t0)             # Timer fires immediately
    sw      zero, 4(t0)

    # Wait for both to be pending in mip
    li      t1, 1000
1:
    csrr    t0, mip
    andi    t0, t0, 0x88            # Check MTIP (7) and MSIP (3)
    li      t2, 0x88
    beq     t0, t2, both_pending
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail               # Timeout

both_pending:
    # Enable both interrupts
    li      t0, 0x88                # MSIE + MTIE
    csrs    mie, t0

    # Clear interrupt count
    la      t0, int_count
    sw      zero, 0(t0)

    # Enable global interrupts
    li      t0, 0x08                # MIE
    csrs    mstatus, t0

    # Wait for first interrupt
    li      t1, 1000
1:
    la      t0, int_count
    lw      t2, 0(t0)
    bnez    t2, got_first
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail

got_first:
    # Verify first interrupt was MSI (cause 3), not MTI (cause 7)
    la      t0, causes
    lw      t1, 0(t0)
    li      t2, 0x80000003          # MSI cause
    bne     t1, t2, test_fail       # FAIL: Should be MSI (higher priority)

    # Wait for second interrupt (MTI)
    li      t1, 1000
1:
    la      t0, int_count
    lw      t2, 0(t0)
    li      t3, 2
    bge     t2, t3, got_second
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail

got_second:
    # Verify second interrupt was MTI (cause 7)
    la      t0, causes
    lw      t1, 4(t0)
    li      t2, 0x80000007          # MTI cause
    bne     t1, t2, test_fail

    # Success - MSI had priority over MTI
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
    # Save cause to array
    csrr    t0, mcause

    la      t1, int_count
    lw      t2, 0(t1)

    la      t1, causes
    slli    t3, t2, 2               # t3 = index * 4
    add     t1, t1, t3
    sw      t0, 0(t1)

    # Increment count
    la      t1, int_count
    addi    t2, t2, 1
    sw      t2, 0(t1)

    # Clear the interrupt that fired
    li      t1, 0x80000003          # MSI
    beq     t0, t1, clear_msi
    li      t1, 0x80000007          # MTI
    beq     t0, t1, clear_mti
    mret

clear_msi:
    li      t0, 0x02000000
    sw      zero, 0(t0)
    mret

clear_mti:
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
causes:         .word 0, 0, 0, 0
