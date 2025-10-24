# Test Program: AMOADD.W - Atomic Add (Compact Version)
# Tests AMOADD.W instruction including overflow
# Target: RV32IA

.section .text
.globl _start

_start:
    lui     a0, 0x1000

    #========================================
    # Test 1: Basic AMOADD.W
    #========================================
    li      t0, 10
    sw      t0, 0(a0)

    li      t1, 5
    amoadd.w t2, t1, (a0)

    li      t3, 10
    bne     t2, t3, fail

    lw      t4, 0(a0)
    li      t5, 15
    bne     t4, t5, fail

    #========================================
    # Test 2: Add Negative (subtraction)
    #========================================
    li      t0, 100
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, -30
    amoadd.w t2, t1, (a1)

    li      t3, 100
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, 70
    bne     t4, t5, fail

    #========================================
    # Test 3: Overflow (INT_MAX + 1 = INT_MIN)
    #========================================
    lui     t0, 0x7FFFF
    ori     t0, t0, 0x7FF       # INT_MAX
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 1
    amoadd.w t2, t1, (a1)

    lui     t3, 0x7FFFF
    ori     t3, t3, 0x7FF
    bne     t2, t3, fail

    lw      t4, 8(a0)
    lui     t5, 0x80000         # INT_MIN
    bne     t4, t5, fail

pass:
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
