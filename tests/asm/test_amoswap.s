# Test Program: AMOSWAP.W - Atomic Swap (Compact Version)
# Tests AMOSWAP.W instruction with key test cases
# Target: RV32IA

.section .text
.globl _start

_start:
    # Initialize base address
    lui     a0, 0x1000          # a0 = 0x1000 (base address)

    #========================================
    # Test 1: Basic AMOSWAP.W
    #========================================
test1_basic:
    li      t0, 42
    sw      t0, 0(a0)           # M[a0] = 42

    li      t1, 100
    amoswap.w t2, t1, (a0)      # t2 = M[a0] (42), M[a0] = 100

    # Verify returned value
    li      t3, 42
    bne     t2, t3, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 100
    bne     t4, t5, fail

    #========================================
    # Test 2: Swap with Negative Value
    #========================================
test2_negative:
    li      t0, 50
    sw      t0, 4(a0)

    addi    a1, a0, 4
    li      t1, -25
    amoswap.w t2, t1, (a1)

    li      t3, 50
    bne     t2, t3, fail

    lw      t4, 4(a0)
    li      t5, -25
    bne     t4, t5, fail

    #========================================
    # Test 3: Swap at Different Address
    #========================================
test3_different_addr:
    li      t0, 111
    sw      t0, 8(a0)

    addi    a1, a0, 8
    li      t1, 222
    amoswap.w t2, t1, (a1)

    li      t3, 111
    bne     t2, t3, fail

    lw      t4, 8(a0)
    li      t5, 222
    bne     t4, t5, fail

    #========================================
    # All tests passed
    #========================================
pass:
    li      a0, 0               # Return 0 (success)
    li      a7, 93              # Exit syscall
    ecall

fail:
    li      a0, 1               # Return 1 (failure)
    li      a7, 93
    ecall
