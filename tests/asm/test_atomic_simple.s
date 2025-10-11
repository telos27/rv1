# Test Program: Basic Atomic Operations (A Extension)
# Tests LR/SC and basic AMO instructions
# Target: RV32IA (or RV64IA when XLEN=64)

.section .text
.globl _start

_start:
    # Initialize memory location with test value
    lui     a0, 0x1000          # a0 = base address (0x1000)
    li      t0, 42              # t0 = 42
    sw      t0, 0(a0)           # M[a0] = 42

    #========================================
    # Test 1: LR.W / SC.W (Load-Reserved / Store-Conditional)
    #========================================
test_lr_sc:
    # LR.W: Load reserved
    lr.w    t1, (a0)            # t1 = M[a0] (42), reserve a0

    # Verify loaded value
    li      t2, 42
    bne     t1, t2, fail        # If t1 != 42, fail

    # Increment
    addi    t1, t1, 1           # t1 = 43

    # SC.W: Store conditional (should succeed)
    sc.w    t3, t1, (a0)        # M[a0] = 43 if reservation valid, t3 = 0 if success

    # Verify SC succeeded (t3 == 0)
    bnez    t3, fail            # If t3 != 0 (failure), fail

    # Verify stored value
    lw      t4, 0(a0)           # t4 = M[a0]
    li      t5, 43
    bne     t4, t5, fail        # If t4 != 43, fail

    #========================================
    # Test 2: AMOSWAP.W (Atomic Swap)
    #========================================
test_amoswap:
    li      t0, 100
    sw      t0, 0(a0)           # M[a0] = 100

    li      t1, 200
    amoswap.w t2, t1, (a0)      # t2 = M[a0] (100), M[a0] = 200

    # Verify returned value (old value)
    li      t3, 100
    bne     t2, t3, fail        # If t2 != 100, fail

    # Verify stored value (new value)
    lw      t4, 0(a0)
    li      t5, 200
    bne     t4, t5, fail        # If t4 != 200, fail

    #========================================
    # Test 3: AMOADD.W (Atomic Add)
    #========================================
test_amoadd:
    li      t0, 10
    sw      t0, 0(a0)           # M[a0] = 10

    li      t1, 5
    amoadd.w t2, t1, (a0)       # t2 = M[a0] (10), M[a0] = 10 + 5 = 15

    # Verify returned value (old value)
    li      t3, 10
    bne     t2, t3, fail        # If t2 != 10, fail

    # Verify stored value (new value)
    lw      t4, 0(a0)
    li      t5, 15
    bne     t4, t5, fail        # If t4 != 15, fail

    #========================================
    # Test 4: AMOXOR.W (Atomic XOR)
    #========================================
test_amoxor:
    li      t0, 0xFF
    sw      t0, 0(a0)           # M[a0] = 0xFF

    li      t1, 0x0F
    amoxor.w t2, t1, (a0)       # t2 = M[a0] (0xFF), M[a0] = 0xFF ^ 0x0F = 0xF0

    # Verify returned value
    li      t3, 0xFF
    bne     t2, t3, fail        # If t2 != 0xFF, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 0xF0
    bne     t4, t5, fail        # If t4 != 0xF0, fail

    #========================================
    # Test 5: AMOAND.W (Atomic AND)
    #========================================
test_amoand:
    li      t0, 0xFF
    sw      t0, 0(a0)           # M[a0] = 0xFF

    li      t1, 0x0F
    amoand.w t2, t1, (a0)       # t2 = M[a0] (0xFF), M[a0] = 0xFF & 0x0F = 0x0F

    # Verify returned value
    li      t3, 0xFF
    bne     t2, t3, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 0x0F
    bne     t4, t5, fail

    #========================================
    # Test 6: AMOOR.W (Atomic OR)
    #========================================
test_amoor:
    li      t0, 0xF0
    sw      t0, 0(a0)           # M[a0] = 0xF0

    li      t1, 0x0F
    amoor.w t2, t1, (a0)        # t2 = M[a0] (0xF0), M[a0] = 0xF0 | 0x0F = 0xFF

    # Verify returned value
    li      t3, 0xF0
    bne     t2, t3, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 0xFF
    bne     t4, t5, fail

    #========================================
    # Test 7: AMOMIN.W (Atomic Signed Min)
    #========================================
test_amomin:
    li      t0, 10
    sw      t0, 0(a0)           # M[a0] = 10

    li      t1, 5
    amomin.w t2, t1, (a0)       # t2 = M[a0] (10), M[a0] = min(10, 5) = 5

    # Verify returned value
    li      t3, 10
    bne     t2, t3, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 5
    bne     t4, t5, fail

    #========================================
    # Test 8: AMOMAX.W (Atomic Signed Max)
    #========================================
test_amomax:
    li      t0, 5
    sw      t0, 0(a0)           # M[a0] = 5

    li      t1, 10
    amomax.w t2, t1, (a0)       # t2 = M[a0] (5), M[a0] = max(5, 10) = 10

    # Verify returned value
    li      t3, 5
    bne     t2, t3, fail

    # Verify stored value
    lw      t4, 0(a0)
    li      t5, 10
    bne     t4, t5, fail

    #========================================
    # All tests passed
    #========================================
pass:
    li      a0, 0               # Return 0 (success)
    j       done

fail:
    li      a0, 1               # Return 1 (failure)
    j       done

done:
    # Infinite loop (halt)
    j       done

.section .data
# No data section needed for this test
