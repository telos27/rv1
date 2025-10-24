# Test Edge Cases: Division and Remainder Operations
# Tests DIV, DIVU, REM, REMU edge cases per RISC-V specification
# RISC-V RV32M Extension Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: Division by zero (per RISC-V spec)
    #===========================================
    # DIV by zero: quotient = -1
    li x5, 100
    li x6, 0
    div x7, x5, x6         # x7 = -1 (0xFFFFFFFF per spec)
    sw x7, 0(x10)          # Store result

    # DIVU by zero: quotient = 2^XLEN - 1
    li x5, 100
    li x6, 0
    divu x7, x5, x6        # x7 = 0xFFFFFFFF (2^32 - 1 per spec)
    sw x7, 4(x10)          # Store result

    # REM by zero: remainder = dividend
    li x5, 100
    li x6, 0
    rem x7, x5, x6         # x7 = 100 (dividend per spec)
    sw x7, 8(x10)          # Store result

    # REMU by zero: remainder = dividend
    li x5, 100
    li x6, 0
    remu x7, x5, x6        # x7 = 100 (dividend per spec)
    sw x7, 12(x10)         # Store result

    #===========================================
    # Test 2: Division overflow (INT_MIN / -1)
    #===========================================
    # This is the ONLY overflow case in division
    # INT_MIN / -1 should return INT_MIN (per RISC-V spec)
    lui x5, 0x80000        # x5 = 0x80000000 (INT_MIN = -2^31)
    li x6, -1              # x6 = -1
    div x7, x5, x6         # x7 = 0x80000000 (INT_MIN, overflow per spec)
    sw x7, 16(x10)         # Store result

    # Remainder for INT_MIN / -1 should be 0
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, -1
    rem x7, x5, x6         # x7 = 0 (per spec)
    sw x7, 20(x10)         # Store result

    #===========================================
    # Test 3: INT_MIN division cases
    #===========================================
    # INT_MIN / 1 = INT_MIN
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, 1
    div x7, x5, x6         # x7 = INT_MIN
    sw x7, 24(x10)         # Store result

    # INT_MIN / 2 = -2^30
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, 2
    div x7, x5, x6         # x7 = 0xC0000000 (-2^30)
    sw x7, 28(x10)         # Store result

    # INT_MIN / INT_MIN = 1
    lui x5, 0x80000        # x5 = INT_MIN
    lui x6, 0x80000        # x6 = INT_MIN
    div x7, x5, x6         # x7 = 1
    sw x7, 32(x10)         # Store result

    # INT_MIN % 2 = 0
    lui x5, 0x80000        # x5 = INT_MIN
    li x6, 2
    rem x7, x5, x6         # x7 = 0
    sw x7, 36(x10)         # Store result

    #===========================================
    # Test 4: INT_MAX division cases
    #===========================================
    # INT_MAX / 1 = INT_MAX
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = 0x7FFFFFFF (INT_MAX)
    li x6, 1
    div x7, x5, x6         # x7 = INT_MAX
    sw x7, 40(x10)         # Store result

    # INT_MAX / -1 = -INT_MAX
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, -1
    div x7, x5, x6         # x7 = 0x80000001 (-INT_MAX)
    sw x7, 44(x10)         # Store result

    # INT_MAX / 2 = 2^30 - 1
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, 2
    div x7, x5, x6         # x7 = 0x3FFFFFFF
    sw x7, 48(x10)         # Store result

    # INT_MAX % 2 = 1
    lui x5, 0x7FFFF
    addi x5, x5, 0x7FF     # x5 = INT_MAX
    li x6, 2
    rem x7, x5, x6         # x7 = 1
    sw x7, 52(x10)         # Store result

    #===========================================
    # Test 5: Unsigned division edge cases (DIVU/REMU)
    #===========================================
    # UINT_MAX / 1 = UINT_MAX
    li x5, -1              # x5 = 0xFFFFFFFF (UINT_MAX)
    li x6, 1
    divu x7, x5, x6        # x7 = 0xFFFFFFFF
    sw x7, 56(x10)         # Store result

    # UINT_MAX / 2 = 0x7FFFFFFF
    li x5, -1              # x5 = UINT_MAX
    li x6, 2
    divu x7, x5, x6        # x7 = 0x7FFFFFFF
    sw x7, 60(x10)         # Store result

    # UINT_MAX % 2 = 1
    li x5, -1              # x5 = UINT_MAX
    li x6, 2
    remu x7, x5, x6        # x7 = 1
    sw x7, 64(x10)         # Store result

    # 0x80000000 / 2 (unsigned) = 0x40000000
    lui x5, 0x80000        # x5 = 0x80000000
    li x6, 2
    divu x7, x5, x6        # x7 = 0x40000000
    sw x7, 68(x10)         # Store result

    # UINT_MAX / UINT_MAX = 1
    li x5, -1              # x5 = UINT_MAX
    li x6, -1              # x6 = UINT_MAX
    divu x7, x5, x6        # x7 = 1
    sw x7, 72(x10)         # Store result

    #===========================================
    # Test 6: Division rounding behavior
    #===========================================
    # Signed division rounds toward zero
    # 7 / 2 = 3 (not 4)
    li x5, 7
    li x6, 2
    div x7, x5, x6         # x7 = 3
    sw x7, 76(x10)         # Store result

    # -7 / 2 = -3 (not -4, rounds toward zero)
    li x5, -7
    li x6, 2
    div x7, x5, x6         # x7 = -3 (0xFFFFFFFD)
    sw x7, 80(x10)         # Store result

    # 7 % 2 = 1
    li x5, 7
    li x6, 2
    rem x7, x5, x6         # x7 = 1
    sw x7, 84(x10)         # Store result

    # -7 % 2 = -1 (remainder has same sign as dividend)
    li x5, -7
    li x6, 2
    rem x7, x5, x6         # x7 = -1 (0xFFFFFFFF)
    sw x7, 88(x10)         # Store result

    #===========================================
    # Test 7: Negative divisor cases
    #===========================================
    # Positive / Negative
    li x5, 100
    li x6, -10
    div x7, x5, x6         # x7 = -10 (0xFFFFFFF6)
    sw x7, 92(x10)         # Store result

    # Negative / Negative
    li x5, -100
    li x6, -10
    div x7, x5, x6         # x7 = 10
    sw x7, 96(x10)         # Store result

    # Positive % Negative (remainder has sign of dividend)
    li x5, 100
    li x6, -30
    rem x7, x5, x6         # x7 = 10 (100 = -30*(-3) + 10)
    sw x7, 100(x10)        # Store result

    # Negative % Positive (remainder has sign of dividend)
    li x5, -100
    li x6, 30
    rem x7, x5, x6         # x7 = -10 (0xFFFFFFF6)
    sw x7, 104(x10)        # Store result

    #===========================================
    # Test 8: Zero dividend cases
    #===========================================
    # 0 / anything (non-zero) = 0
    li x5, 0
    li x6, 12345
    div x7, x5, x6         # x7 = 0
    sw x7, 108(x10)        # Store result

    # 0 % anything (non-zero) = 0
    li x5, 0
    li x6, 12345
    rem x7, x5, x6         # x7 = 0
    sw x7, 112(x10)        # Store result

    #===========================================
    # Test 9: Small divisor/dividend cases
    #===========================================
    # 1 / 1 = 1
    li x5, 1
    li x6, 1
    div x7, x5, x6         # x7 = 1
    sw x7, 116(x10)        # Store result

    # 1 / 2 = 0 (rounds toward zero)
    li x5, 1
    li x6, 2
    div x7, x5, x6         # x7 = 0
    sw x7, 120(x10)        # Store result

    # 1 % 2 = 1
    li x5, 1
    li x6, 2
    rem x7, x5, x6         # x7 = 1
    sw x7, 124(x10)        # Store result

    #===========================================
    # Verification Section
    #===========================================
    # Load back critical results for verification
    lw x5, 0(x10)          # DIV by zero should be -1
    lw x6, 16(x10)         # INT_MIN / -1 should be INT_MIN
    lw x7, 20(x10)         # INT_MIN % -1 should be 0
    lw x8, 80(x10)         # -7 / 2 should be -3

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
