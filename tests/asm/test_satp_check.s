# Minimal test to check SATP value at start
.option norvc

.section .text
.globl _start

_start:
    # Stage 1: Check SATP
    li      x29, 1

    # Read SATP
    csrr    t0, satp

    # Store it in t1 for inspection
    mv      t1, t0

    # Check if zero
    bnez    t0, fail

    # Stage 2: SATP was zero
    li      x29, 2
    j       pass

pass:
    li      x28, 0xDEADBEEF
    ebreak

fail:
    li      x28, 0xDEADDEAD
    ebreak
