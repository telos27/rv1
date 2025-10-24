# Test Edge Cases: Integer Arithmetic
# Tests INT_MIN, INT_MAX, overflow, underflow, and zero operations
# RISC-V RV32I Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: INT_MAX operations
    #===========================================
    lui x5, 0x80000        # x5 = 0x80000000
    addi x5, x5, -1        # x5 = 0x7FFFFFFF (INT_MAX)

    # INT_MAX + 1 should overflow to INT_MIN
    addi x6, x5, 1         # x6 = 0x80000000 (INT_MIN)
    sw x6, 0(x10)          # Store result

    # INT_MAX + INT_MAX should overflow
    add x7, x5, x5         # x7 = 0xFFFFFFFE (-2)
    sw x7, 4(x10)          # Store result

    #===========================================
    # Test 2: INT_MIN operations
    #===========================================
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN)

    # INT_MIN - 1 should underflow to INT_MAX
    addi x6, x5, -1        # x6 = 0x7FFFFFFF (INT_MAX)
    sw x6, 8(x10)          # Store result

    # INT_MIN + INT_MIN should overflow
    add x7, x5, x5         # x7 = 0x00000000 (wraps to 0)
    sw x7, 12(x10)         # Store result

    # INT_MIN - INT_MIN should equal 0
    sub x8, x5, x5         # x8 = 0
    sw x8, 16(x10)         # Store result

    #===========================================
    # Test 3: Zero operations
    #===========================================
    li x5, 0               # x5 = 0

    # 0 + 0 = 0
    add x6, x5, x5         # x6 = 0
    sw x6, 20(x10)         # Store result

    # 0 - 0 = 0
    sub x7, x5, x5         # x7 = 0
    sw x7, 24(x10)         # Store result

    # 0 XOR 0 = 0
    xor x8, x5, x5         # x8 = 0
    sw x8, 28(x10)         # Store result

    # 0 OR 0 = 0
    or x9, x5, x5          # x9 = 0
    sw x9, 32(x10)         # Store result

    # 0 AND 0 = 0
    and x11, x5, x5        # x11 = 0
    sw x11, 36(x10)        # Store result

    #===========================================
    # Test 4: Signed comparison edge cases
    #===========================================
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN = -2147483648)
    lui x6, 0x7FFFF
    addi x6, x6, 0x7FF     # x6 = 0x7FFFFFFF (INT_MAX = 2147483647)

    # INT_MIN < INT_MAX (signed)
    slt x7, x5, x6         # x7 = 1 (true)
    sw x7, 40(x10)         # Store result

    # INT_MAX < INT_MIN (signed) should be false
    slt x8, x6, x5         # x8 = 0 (false)
    sw x8, 44(x10)         # Store result

    # INT_MIN < 0 (signed)
    slt x9, x5, x0         # x9 = 1 (true)
    sw x9, 48(x10)         # Store result

    #===========================================
    # Test 5: Unsigned comparison edge cases
    #===========================================
    lui x5, 0x80000        # x5 = 0x80000000
    lui x6, 0x7FFFF
    addi x6, x6, 0x7FF     # x6 = 0x7FFFFFFF

    # 0x80000000 > 0x7FFFFFFF (unsigned)
    sltu x7, x6, x5        # x7 = 1 (true, since 0x7FFF... < 0x8000... unsigned)
    sw x7, 52(x10)         # Store result

    # 0xFFFFFFFF > 0x00000000 (unsigned)
    li x8, -1              # x8 = 0xFFFFFFFF
    sltu x9, x0, x8        # x9 = 1 (true)
    sw x9, 56(x10)         # Store result

    #===========================================
    # Test 6: Negation edge cases
    #===========================================
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN)

    # -INT_MIN should overflow to INT_MIN (two's complement)
    sub x6, x0, x5         # x6 = 0 - INT_MIN = INT_MIN (overflow)
    sw x6, 60(x10)         # Store result

    # -0 should equal 0
    sub x7, x0, x0         # x7 = 0
    sw x7, 64(x10)         # Store result

    # -(INT_MAX) should equal INT_MIN + 1
    lui x8, 0x7FFFF
    addi x8, x8, 0x7FF     # x8 = INT_MAX
    sub x9, x0, x8         # x9 = -INT_MAX = 0x80000001
    sw x9, 68(x10)         # Store result

    #===========================================
    # Test 7: Shift edge cases
    #===========================================
    li x5, 1

    # Left shift by 31 (maximum for 32-bit)
    slli x6, x5, 31        # x6 = 0x80000000
    sw x6, 72(x10)         # Store result

    # Right shift INT_MIN by 31 (arithmetic)
    lui x7, 0x80000        # x7 = INT_MIN
    srai x8, x7, 31        # x8 = 0xFFFFFFFF (sign extended)
    sw x8, 76(x10)         # Store result

    # Right shift INT_MIN by 31 (logical)
    srli x9, x7, 31        # x9 = 0x00000001 (zero filled)
    sw x9, 80(x10)         # Store result

    #===========================================
    # Verification Section
    #===========================================
    # Load and verify key results
    lw x5, 0(x10)          # Should be 0x80000000 (INT_MAX + 1)
    lw x6, 8(x10)          # Should be 0x7FFFFFFF (INT_MIN - 1)
    lw x7, 40(x10)         # Should be 1 (INT_MIN < INT_MAX)
    lw x8, 60(x10)         # Should be 0x80000000 (-INT_MIN overflow)

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
