# Test Program: AMOMIN/AMOMAX/AMOMINU/AMOMAXU (Compact)
# Tests signed and unsigned atomic min/max
# Target: RV32IA

.section .text
.globl _start

_start:
    lui     a0, 0x1000

    #========================================
    # Test 1: AMOMIN.W - Signed minimum
    #========================================
    li      t0, 10
    sw      t0, 0(a0)

    li      t1, 5
    amomin.w t2, t1, (a0)

    li      t3, 10
    bne     t2, t3, fail

    lw      t4, 0(a0)
    li      t5, 5
    bne     t4, t5, fail

    #========================================
    # Test 2: AMOMAX.W - Signed maximum
    #========================================
    li      t0, 5
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, 10
    amomax.w t2, t1, (a1)

    li      t3, 5
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, 10
    bne     t4, t5, fail

    #========================================
    # Test 3: AMOMINU.W - Unsigned (0xFFFFFFFF vs 100)
    #========================================
    li      t0, -1              # 0xFFFFFFFF
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 100
    amominu.w t2, t1, (a1)

    li      t3, -1
    bne     t2, t3, fail

    lw      t4, 8(a0)
    li      t5, 100             # 100 is smaller unsigned
    bne     t4, t5, fail

    #========================================
    # Test 4: AMOMAXU.W - Unsigned
    #========================================
    li      t0, 100
    sw      t0, 12(a0)

    addi    a1, a0, 12
    li      t1, -1              # 0xFFFFFFFF
    amomaxu.w t2, t1, (a1)

    li      t3, 100
    bne     t2, t3, fail

    lw      t4, 12(a0)
    li      t5, -1              # 0xFFFFFFFF is larger unsigned
    bne     t4, t5, fail

pass:
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
