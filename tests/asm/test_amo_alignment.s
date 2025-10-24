# Test Program: AMO Alignment (Compact)
# Tests AMO operations at various aligned addresses
# Target: RV32IA

.section .text
.globl _start

_start:
    lui     a0, 0x1000

    #========================================
    # Test 1: AMOSWAP at offset 0
    #========================================
    li      t0, 0x11111111
    sw      t0, 0(a0)

    li      t1, 0x22222222
    amoswap.w t2, t1, (a0)

    lui     t3, 0x11111
    ori     t3, t3, 0x111
    bne     t2, t3, fail

    #========================================
    # Test 2: AMOADD at offset 4
    #========================================
    li      t0, 100
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, 50
    amoadd.w t2, t1, (a1)

    li      t3, 100
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, 150
    bne     t4, t5, fail

    #========================================
    # Test 3: AMOAND at offset 8
    #========================================
    li      t0, 0xFFFFFFFF
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 0x0000FFFF
    amoand.w t2, t1, (a1)

    li      t3, -1
    bne     t2, t3, fail

pass:
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
