# RV32M Basic Test
# Tests basic multiply and divide instructions
# Author: RV1 Project (M Extension)
# Date: 2025-10-10

.section .text
.globl _start

_start:
    # Initialize stack pointer (not used in this test)
    li sp, 0x10000

    #=========================================================================
    # Test 1: MUL (Multiply - lower 32 bits)
    #=========================================================================
test_mul:
    li a0, 100
    li a1, 200
    mul a2, a0, a1          # a2 = 100 * 200 = 20000 (0x4E20)

    # Verify result
    li t0, 20000
    bne a2, t0, test_fail

    #=========================================================================
    # Test 2: MUL with negative numbers
    #=========================================================================
test_mul_neg:
    li a3, -10
    li a4, 5
    mul a5, a3, a4          # a5 = -10 * 5 = -50 (0xFFFFFFCE)

    # Verify result
    li t1, -50
    bne a5, t1, test_fail

    #=========================================================================
    # Test 3: MULH (Multiply high signed)
    #=========================================================================
test_mulh:
    li a0, 0x80000000       # -2147483648 (most negative 32-bit number)
    li a1, 2
    mulh a2, a0, a1         # High 32 bits of (-2147483648 * 2)

    # Result should be -1 (0xFFFFFFFF) since result is -4294967296
    li t2, -1
    bne a2, t2, test_fail

    #=========================================================================
    # Test 4: MULHU (Multiply high unsigned)
    #=========================================================================
test_mulhu:
    li a3, 0xFFFFFFFF       # 4294967295 (max unsigned 32-bit)
    li a4, 2
    mulhu a5, a3, a4        # High 32 bits of (4294967295 * 2)

    # Result should be 1 (since 4294967295 * 2 = 8589934590 = 0x1FFFFFFFE)
    li t3, 1
    bne a5, t3, test_fail

    #=========================================================================
    # Test 5: MULHSU (Multiply high signed-unsigned)
    #=========================================================================
test_mulhsu:
    li a0, -1               # -1 as signed
    li a1, 0xFFFFFFFF       # 4294967295 as unsigned
    mulhsu a2, a0, a1       # High 32 bits of (-1 * 4294967295)

    # Result should be 0 (since -1 * 4294967295 = -4294967295 = 0xFFFFFFFF00000001)
    li t4, 0
    bne a2, t4, test_fail

    #=========================================================================
    # Test 6: DIV (Division signed)
    #=========================================================================
test_div:
    li a3, 100
    li a4, 5
    div a5, a3, a4          # a5 = 100 / 5 = 20

    # Verify result
    li t5, 20
    bne a5, t5, test_fail

    #=========================================================================
    # Test 7: DIV with negative dividend
    #=========================================================================
test_div_neg:
    li a0, -100
    li a1, 5
    div a2, a0, a1          # a2 = -100 / 5 = -20

    # Verify result
    li t0, -20
    bne a2, t0, test_fail

    #=========================================================================
    # Test 8: DIVU (Division unsigned)
    #=========================================================================
test_divu:
    li a3, 0xFFFFFFFF       # 4294967295 unsigned
    li a4, 2
    divu a5, a3, a4         # a5 = 4294967295 / 2 = 2147483647 (0x7FFFFFFF)

    # Verify result
    li t1, 0x7FFFFFFF
    bne a5, t1, test_fail

    #=========================================================================
    # Test 9: REM (Remainder signed)
    #=========================================================================
test_rem:
    li a0, 100
    li a1, 7
    rem a2, a0, a1          # a2 = 100 % 7 = 2

    # Verify result
    li t2, 2
    bne a2, t2, test_fail

    #=========================================================================
    # Test 10: REMU (Remainder unsigned)
    #=========================================================================
test_remu:
    li a3, 0xFFFFFFFF       # 4294967295 unsigned
    li a4, 10
    remu a5, a3, a4         # a5 = 4294967295 % 10 = 5

    # Verify result
    li t3, 5
    bne a5, t3, test_fail

    #=========================================================================
    # Test 11: Division by zero (special case)
    #=========================================================================
test_div_by_zero:
    li a0, 100
    li a1, 0
    div a2, a0, a1          # Quotient should be -1 per RISC-V spec
    rem a3, a0, a1          # Remainder should be dividend (100)

    # Verify quotient = -1
    li t4, -1
    bne a2, t4, test_fail

    # Verify remainder = dividend
    li t5, 100
    bne a3, t5, test_fail

    #=========================================================================
    # Test 12: Overflow case (MIN_INT / -1)
    #=========================================================================
test_div_overflow:
    li a4, 0x80000000       # Most negative 32-bit number
    li a5, -1
    div s0, a4, a5          # Quotient should be MIN_INT per RISC-V spec
    rem s1, a4, a5          # Remainder should be 0

    # Verify quotient = MIN_INT
    li t0, 0x80000000
    bne s0, t0, test_fail

    # Verify remainder = 0
    li t1, 0
    bne s1, t1, test_fail

    #=========================================================================
    # All tests passed
    #=========================================================================
test_pass:
    li a0, 0x600D           # GOOD (pass indicator)
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak                  # Exit simulation

test_fail:
    li a0, 0xBAD            # BAD (fail indicator)
    nop                     # Pipeline drain
    nop
    nop
    nop
    ebreak                  # Exit simulation
