# Test Program: AMO Memory Ordering (Compact)
# Tests atomic operations with .aq and .rl bits
# Target: RV32IA

.section .text
.globl _start

_start:
    lui     a0, 0x1000

    #========================================
    # Test 1: AMOSWAP.W.AQ - Acquire
    #========================================
    li      t0, 42
    sw      t0, 0(a0)

    li      t1, 100
    amoswap.w.aq t2, t1, (a0)

    li      t3, 42
    bne     t2, t3, fail

    lw      t4, 0(a0)
    li      t5, 100
    bne     t4, t5, fail

    #========================================
    # Test 2: AMOSWAP.W.RL - Release
    #========================================
    li      t0, 200
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, 300
    amoswap.w.rl t2, t1, (a1)

    li      t3, 200
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, 300
    bne     t4, t5, fail

    #========================================
    # Test 3: AMOSWAP.W.AQRL - Both
    #========================================
    li      t0, 500
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 600
    amoswap.w.aqrl t2, t1, (a1)

    li      t3, 500
    bne     t2, t3, fail

    lw      t4, 8(a0)
    li      t5, 600
    bne     t4, t5, fail

pass:
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
