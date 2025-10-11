# Comprehensive DIV/DIVU/REM/REMU test
.section .text
.globl _start

_start:
    # Test 1: Simple signed division - 100 / 4 = 25
    li a0, 100
    li a1, 4
    div a2, a0, a1      # a2 = 25

    # Test 2: Signed division with negative dividend - (-100) / 4 = -25
    li a0, -100
    li a1, 4
    div a3, a0, a1      # a3 = -25

    # Test 3: Signed division with negative divisor - 100 / (-4) = -25
    li a0, 100
    li a1, -4
    div a4, a0, a1      # a4 = -25

    # Test 4: Both negative - (-100) / (-4) = 25
    li a0, -100
    li a1, -4
    div a5, a0, a1      # a5 = 25

    # Test 5: Unsigned division - 100 / 4 = 25
    li a0, 100
    li a1, 4
    divu a6, a0, a1     # a6 = 25

    # Test 6: Signed remainder - 50 % 7 = 1
    li a0, 50
    li a1, 7
    rem a7, a0, a1      # a7 = 1

    # Test 7: Negative remainder - (-50) % 7 = -1
    li a0, -50
    li a1, 7
    rem s0, a0, a1      # s0 = -1

    # Test 8: Unsigned remainder - 50 % 7 = 1
    li a0, 50
    li a1, 7
    remu s1, a0, a1     # s1 = 1

    # Test 9: Division by zero (DIV) - should return -1
    li a0, 100
    li a1, 0
    div s2, a0, a1      # s2 = -1 (0xFFFFFFFF)

    # Test 10: Division by zero (REM) - should return dividend
    li a0, 100
    li a1, 0
    rem s3, a0, a1      # s3 = 100

    # Success marker
    li a0, 0x600D
    ebreak
