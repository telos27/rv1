# test_interrupt_nested_mmode.s - Nested Interrupts in M-mode Test
# Tests that a higher-priority interrupt can nest within a lower-priority handler
# Scenario: MTI fires → handler triggers MSI → MSI nests within MTI handler
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

    # Enable both timer and software interrupts
    li      t0, 0x88                # MSIE + MTIE
    csrs    mie, t0

    # Set timer to fire soon
    li      t0, 0x02004000
    li      t1, 100
    sw      t1, 0(t0)
    sw      zero, 4(t0)

    # Clear counters
    la      t0, int_count
    sw      zero, 0(t0)
    la      t0, nested_flag
    sw      zero, 0(t0)

    # Enable global interrupts
    li      t0, 0x08                # MIE
    csrs    mstatus, t0

    # Wait for both interrupts to complete
    li      t1, 3000
1:
    la      t0, int_count
    lw      t2, 0(t0)
    li      t3, 2                   # Expect 2 interrupts
    bge     t2, t3, done
    addi    t1, t1, -1
    bnez    t1, 1b
    j       test_fail               # Timeout

done:
    # Verify we had nested execution
    la      t0, nested_flag
    lw      t1, 0(t0)
    li      t2, 1
    bne     t1, t2, test_fail       # Should have nested

    # Verify first interrupt was MTI
    la      t0, causes
    lw      t1, 0(t0)
    li      t2, 0x80000007          # MTI
    bne     t1, t2, test_fail

    # Verify second interrupt was MSI (nested)
    la      t0, causes
    lw      t1, 4(t0)
    li      t2, 0x80000003          # MSI
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
    # Check if we're already in handler (nested)
    la      t0, in_handler
    lw      t1, 0(t0)
    bnez    t1, nested_int

    # Not nested - mark that we're in handler
    li      t1, 1
    sw      t1, 0(t0)

    # Save cause
    csrr    t0, mcause
    la      t1, int_count
    lw      t2, 0(t1)
    la      t1, causes
    slli    t3, t2, 2
    add     t1, t1, t3
    sw      t0, 0(t1)

    # Increment count
    la      t1, int_count
    addi    t2, t2, 1
    sw      t2, 0(t1)

    # If this is MTI, trigger MSI for nesting
    li      t1, 0x80000007
    bne     t0, t1, clear_int

    # Trigger MSI
    li      t0, 0x02000000
    li      t1, 1
    sw      t1, 0(t0)

    # Small delay to let nested interrupt fire
    li      t0, 100
1:  addi    t0, t0, -1
    bnez    t0, 1b

    j       clear_int

nested_int:
    # We're nested! Set flag
    la      t0, nested_flag
    li      t1, 1
    sw      t1, 0(t0)

    # Save cause
    csrr    t0, mcause
    la      t1, int_count
    lw      t2, 0(t1)
    la      t1, causes
    slli    t3, t2, 2
    add      t1, t1, t3
    sw      t0, 0(t1)

    # Increment count
    la      t1, int_count
    addi    t2, t2, 1
    sw      t2, 0(t1)

clear_int:
    # Clear the interrupt source
    csrr    t0, mcause
    li      t1, 0x80000003          # MSI
    beq     t0, t1, clear_msi
    li      t1, 0x80000007          # MTI
    beq     t0, t1, clear_mti
    j       handler_exit

clear_msi:
    li      t0, 0x02000000
    sw      zero, 0(t0)
    j       handler_exit

clear_mti:
    li      t0, 0x02004000
    li      t1, 1000000
    sw      t1, 0(t0)
    sw      zero, 4(t0)

handler_exit:
    # Clear in_handler flag
    la      t0, in_handler
    sw      zero, 0(t0)

    mret

# ==============================================================================
# Data Section
# ==============================================================================
.section .data
.align 4
int_count:      .word 0
nested_flag:    .word 0
in_handler:     .word 0
causes:         .word 0, 0, 0, 0
