# Test sequence of M operations
.section .text
.globl _start

_start:
    # Test 1: MUL
    li a0, 5
    li a1, 10
    mul a2, a0, a1          # a2 = 50

    # Test 2: Another MUL
    li a3, 3
    li a4, 7
    mul a5, a3, a4          # a5 = 21

    # Test 3: DIV
    li a0, 100
    li a1, 4
    div s0, a0, a1          # s0 = 25

    # Test 4: REM
    li a0, 50
    li a1, 7
    rem s1, a0, a1          # s1 = 1

    # Mark success
    li a0, 0x600D
    nop
    nop
    nop
    nop
    ebreak
