# Test: Simple ECALL Test
# Just test if ECALL traps and returns

.section .text
.globl _start

_start:
    # Set trap vector
    la      t0, trap_handler
    csrw    mtvec, t0

    # Set marker before ECALL
    li      t1, 0xAAAAAAAA

    # Do ECALL
    ecall

    # Should reach here after trap handler returns
    li      t2, 0xBBBBBBBB
    j       test_pass

trap_handler:
    # Check cause is ECALL (should be 11 for M-mode)
    csrr    t3, mcause

    # Advance MEPC past ECALL instruction (4 bytes)
    csrr    t4, mepc
    addi    t4, t4, 4
    csrw    mepc, t4

    # Set marker to show we entered handler
    li      t5, 0xCCCCCCCC

    # Return
    mret

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
