# Simple DIV test to debug the division bug
# Test: 100 ÷ 4 = 25 (0x19)

.section .text
.globl _start

_start:
    # Test 1: Simple division - 100 ÷ 4 = 25
    li a0, 100          # Dividend = 100
    li a1, 4            # Divisor = 4
    div a2, a0, a1      # a2 should be 25 (0x19)

    # Test 2: Another simple case - 50 ÷ 5 = 10
    li a3, 50           # Dividend = 50
    li a4, 5            # Divisor = 5
    div a5, a3, a4      # a5 should be 10 (0x0A)

    # Test 3: Division with remainder - 25 ÷ 7 = 3
    li a6, 25           # Dividend = 25
    li a7, 7            # Divisor = 7
    div s0, a6, a7      # s0 should be 3 (0x03)

    # Test 4: Verify REM works - 25 % 7 = 4
    rem s1, a6, a7      # s1 should be 4 (0x04)

    # Success marker
    li a0, 0x600D
    ebreak
