# Test Program: AMOAND/AMOOR/AMOXOR - Logical AMOs (Compact)
# Tests atomic logical operations
# Target: RV32IA

.section .text
.globl _start

_start:
    lui     a0, 0x1000

    #========================================
    # Test 1: AMOAND.W - Clear upper bits
    #========================================
    li      t0, 0xFF
    sw      t0, 0(a0)

    li      t1, 0x0F
    amoand.w t2, t1, (a0)

    li      t3, 0xFF
    bne     t2, t3, fail

    lw      t4, 0(a0)
    li      t5, 0x0F
    bne     t4, t5, fail

    #========================================
    # Test 2: AMOOR.W - Set bits
    #========================================
    li      t0, 0xF0
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, 0x0F
    amoor.w t2, t1, (a1)

    li      t3, 0xF0
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, 0xFF
    bne     t4, t5, fail

    #========================================
    # Test 3: AMOXOR.W - Toggle bits
    #========================================
    li      t0, 0xFF
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 0x0F
    amoxor.w t2, t1, (a1)

    li      t3, 0xFF
    bne     t2, t3, fail

    lw      t4, 8(a0)
    li      t5, 0xF0
    bne     t4, t5, fail

pass:
    li      a0, 0
    li      a7, 93
    ecall

fail:
    li      a0, 1
    li      a7, 93
    ecall
