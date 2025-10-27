# test_interrupt_mtimer.s - Machine Timer Interrupt Test
# Tests end-to-end timer interrupt delivery via CLINT
# Author: RV1 Project - Phase 1.5
# Date: 2025-10-27

.include "tests/asm/include/priv_test_macros.s"

.section .text
.global _start

_start:
    # Initialize test
    li      sp, 0x80010000          # Set stack pointer

    # Clear any pending interrupts
    csrw    mip, zero

    # Set up M-mode trap handler
    SET_MTVEC_DIRECT m_trap_handler

    # Test Stage 1: Timer interrupt delivery
    # =========================================

    # Set MTIMECMP to a value in the future (500 cycles)
    li      t0, 0x02004000          # MTIMECMP address
    li      t1, 500                 # Trigger at cycle 500
    sw      t1, 0(t0)               # Write lower 32 bits
    sw      zero, 4(t0)             # Write upper 32 bits (0)

    # Enable timer interrupt in mie (bit 7 = MTIE)
    li      t0, 0x80                # MTIE bit
    csrs    mie, t0

    # Enable global interrupts in mstatus (bit 3 = MIE)
    li      t0, 0x08                # MIE bit
    csrs    mstatus, t0

    # Set flag: waiting for interrupt
    la      t0, interrupt_flag
    sw      zero, 0(t0)

    # Wait for interrupt (should happen within 500 cycles)
    li      t1, 10000               # Large timeout counter
1:
    la      t0, interrupt_flag
    lw      t2, 0(t0)
    bnez    t2, interrupt_received  # If flag set, interrupt occurred
    addi    t1, t1, -1
    bnez    t1, 1b

    # Timeout - interrupt didn't fire - check if MTIP is set in mip
    csrr    t0, mip
    li      t1, 0x80                # MTIP bit
    and     t0, t0, t1
    beqz    t0, test_fail           # MTIP not set = CLINT problem
    # MTIP is set but interrupt didn't fire = interrupt handling problem
    li      a0, 2                   # Exit code 2 = interrupt pending but not delivered
    ebreak

interrupt_received:
    # Test Stage 2: Verify interrupt was timer interrupt
    # ====================================================
    la      t0, trap_cause
    lw      t1, 0(t0)
    li      t2, 0x80000007          # Interrupt bit + cause 7 (MTI)
    bne     t1, t2, test_fail       # Should be timer interrupt

    # Test Stage 3: Verify mip.MTIP was set
    # =======================================
    la      t0, saved_mip
    lw      t1, 0(t0)
    andi    t1, t1, 0x80            # Check bit 7 (MTIP)
    beqz    t1, test_fail           # Should be set

    # Test Stage 4: Clear timer interrupt and verify it clears
    # ==========================================================

    # Read current MTIME
    li      t0, 0x0200BFF8          # MTIME address
    lw      t1, 0(t0)               # Read lower 32 bits
    lw      t2, 4(t0)               # Read upper 32 bits

    # Set MTIMECMP to MTIME + 1000000 (far in future)
    li      t3, 1000000
    add     t1, t1, t3
    li      t0, 0x02004000          # MTIMECMP address
    sw      t1, 0(t0)               # Write lower 32 bits
    sw      t2, 4(t0)               # Write upper 32 bits

    # Small delay to let interrupt clear
    li      t0, 10
1:  addi    t0, t0, -1
    bnez    t0, 1b

    # Check that MTIP is now clear in mip
    csrr    t0, mip
    andi    t0, t0, 0x80            # Check MTIP bit
    bnez    t0, test_fail           # Should be clear now

test_pass:
    # All tests passed
    li      a0, 0                   # Exit code 0
    ebreak                          # Signal test completion

test_fail:
    # Test failed
    li      a0, 1                   # Exit code 1
    ebreak                          # Signal test failure

# ==============================================================================
# M-mode Trap Handler
# ==============================================================================
.align 4
m_trap_handler:
    # Save trap cause
    csrr    t0, mcause
    la      t1, trap_cause
    sw      t0, 0(t1)

    # Save mip value
    csrr    t0, mip
    la      t1, saved_mip
    sw      t0, 0(t1)

    # Set interrupt flag
    li      t0, 1
    la      t1, interrupt_flag
    sw      t0, 0(t1)

    # Return from trap
    mret

# ==============================================================================
# Data Section
# ==============================================================================
.section .data
.align 4
interrupt_flag:     .word 0
trap_cause:         .word 0
saved_mip:          .word 0
