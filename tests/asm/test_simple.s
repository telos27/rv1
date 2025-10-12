# test_simple.s
# Very simple test with a few instructions

.section .text
.globl _start

_start:
    # Test 1: Simple arithmetic
    addi x10, x0, 5      # x10 = 5
    addi x11, x0, 10     # x11 = 10
    add  x12, x10, x11   # x12 = 15

    # Test 2: Subtraction
    sub  x13, x11, x10   # x13 = 5

    # Test 3: Logic operations
    ori  x14, x10, 0xFF  # x14 = 0xFF
    andi x15, x14, 0x0F  # x15 = 0x05

    # End - infinite loop
loop:
    beq  x0, x0, loop    # Infinite loop
