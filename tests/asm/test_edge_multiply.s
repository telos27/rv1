# Test Edge Cases: Multiply Operations
# Tests MULH, MULHU, MULHSU edge cases including INT_MIN, INT_MAX, and overflow
# RISC-V RV32M Extension Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: MUL basic edge cases
    #===========================================
    # 0 × anything = 0
    li x5, 0
    li x6, 12345
    mul x7, x5, x6         # x7 = 0
    sw x7, 0(x10)          # Store result

    # 1 × anything = anything
    li x5, 1
    li x6, 0xABCDEF12
    mul x7, x5, x6         # x7 = 0xABCDEF12
    sw x7, 4(x10)          # Store result

    # -1 × anything = -anything (two's complement)
    li x5, -1              # x5 = 0xFFFFFFFF
    li x6, 42
    mul x7, x5, x6         # x7 = -42 = 0xFFFFFFD6
    sw x7, 8(x10)          # Store result

    #===========================================
    # Test 2: MULH - Signed multiply high (INT_MIN cases)
    #===========================================
    # INT_MIN × INT_MIN (most extreme positive result in high word)
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN = -2^31)
    lui x6, 0x80000        # x6 = 0x80000000 (INT_MIN = -2^31)
    mulh x7, x5, x6        # x7 = upper 32 bits of (-2^31) × (-2^31) = 2^62
                           # Result: 0x40000000
    sw x7, 12(x10)         # Store result

    # INT_MIN × 1 (should give 0xFFFFFFFF in high word)
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, 1
    mulh x7, x5, x6        # x7 = 0xFFFFFFFF (sign extension)
    sw x7, 16(x10)         # Store result

    # INT_MIN × -1 (overflow case: result is 2^31, but in 64-bit it's valid)
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, -1
    mulh x7, x5, x6        # x7 = 0x00000000 (high word of 2^31)
    sw x7, 20(x10)         # Store result

    # INT_MIN × 2 (should be -2^32)
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, 2
    mulh x7, x5, x6        # x7 = 0xFFFFFFFF (high word, negative)
    sw x7, 24(x10)         # Store result

    #===========================================
    # Test 3: MULH - Signed multiply high (INT_MAX cases)
    #===========================================
    # INT_MAX × INT_MAX
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = 0x7FFFFFFF (INT_MAX)
    lui x6, 0x7FFFF
    addi x6, x6, 0x7FF     # x6 = 0x7FFFFFFF (INT_MAX)
    mulh x7, x5, x6        # x7 = upper 32 bits
    sw x7, 28(x10)         # Store result

    # INT_MAX × 2
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, 2
    mulh x7, x5, x6        # x7 = 0x00000000 (high word)
    sw x7, 32(x10)         # Store result

    # INT_MAX × -1
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, -1
    mulh x7, x5, x6        # x7 = 0xFFFFFFFF (sign extension)
    sw x7, 36(x10)         # Store result

    #===========================================
    # Test 4: MULHU - Unsigned multiply high
    #===========================================
    # UINT_MAX × UINT_MAX (0xFFFFFFFF × 0xFFFFFFFF)
    li x5, -1              # x5 = 0xFFFFFFFF
    li x6, -1              # x6 = 0xFFFFFFFF
    mulhu x7, x5, x6       # x7 = 0xFFFFFFFE (high word)
    sw x7, 40(x10)         # Store result

    # UINT_MAX × 2
    li x5, -1              # x5 = 0xFFFFFFFF
    li x6, 2
    mulhu x7, x5, x6       # x7 = 0x00000001 (high word)
    sw x7, 44(x10)         # Store result

    # 0x80000000 × 2 (unsigned)
    lui x5, 0x80000        # x5 = 0x80000000
    li x6, 2
    mulhu x7, x5, x6       # x7 = 0x00000001 (high word)
    sw x7, 48(x10)         # Store result

    # Large × Large unsigned
    lui x5, 0x12345
    addi x5, x5, 0x678     # x5 = 0x12345678
    lui x6, 0xABCDE
    addi x6, x6, 0x7FF     # x6 = 0xABCDEFFF
    mulhu x7, x5, x6       # x7 = high word
    sw x7, 52(x10)         # Store result

    #===========================================
    # Test 5: MULHSU - Signed × Unsigned multiply high
    #===========================================
    # INT_MIN × UINT_MAX (signed × unsigned)
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN, treated as signed)
    li x6, -1              # x6 = 0xFFFFFFFF (UINT_MAX, treated as unsigned)
    mulhsu x7, x5, x6      # x7 = high word
    sw x7, 56(x10)         # Store result

    # -1 (signed) × UINT_MAX (unsigned)
    li x5, -1              # x5 = -1 (signed)
    li x6, -1              # x6 = 0xFFFFFFFF (unsigned)
    mulhsu x7, x5, x6      # x7 = 0xFFFFFFFF (high word, negative result)
    sw x7, 60(x10)         # Store result

    # INT_MAX × UINT_MAX
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = 0x7FFFFFFF (INT_MAX, signed)
    li x6, -1              # x6 = 0xFFFFFFFF (unsigned)
    mulhsu x7, x5, x6      # x7 = high word
    sw x7, 64(x10)         # Store result

    # Positive × Large unsigned
    li x5, 100             # Small positive signed
    lui x6, 0x80000        # Large unsigned
    mulhsu x7, x5, x6      # x7 = high word
    sw x7, 68(x10)         # Store result

    #===========================================
    # Test 6: MUL overflow behavior
    #===========================================
    # Verify MUL only returns lower 32 bits
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, 2
    mul x7, x5, x6         # x7 = 0xFFFFFFFE (lower 32 bits only)
    sw x7, 72(x10)         # Store result

    # Large × Large should overflow in lower word
    lui x5, 0x12345
    addi x5, x5, 0x678     # x5 = 0x12345678
    lui x6, 0x87654
    addi x6, x6, 0x321     # x6 = 0x87654321
    mul x7, x5, x6         # x7 = lower 32 bits only
    sw x7, 76(x10)         # Store result

    #===========================================
    # Test 7: Special multiplication patterns
    #===========================================
    # Powers of 2 multiplication
    li x5, 1
    slli x5, x5, 30        # x5 = 2^30
    li x6, 4               # x6 = 2^2
    mul x7, x5, x6         # x7 = 2^32 lower bits = 0
    sw x7, 80(x10)         # Store result (should be 0)

    mulh x8, x5, x6        # x8 = 2^32 upper bits = 1
    sw x8, 84(x10)         # Store result (should be 1)

    #===========================================
    # Verification Section
    #===========================================
    # Load back critical results for verification
    lw x5, 12(x10)         # INT_MIN × INT_MIN high word
    lw x6, 40(x10)         # UINT_MAX × UINT_MAX high word
    lw x7, 72(x10)         # INT_MAX × 2 lower word

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
