# simple_add.s
# Simple test: Add two numbers
# Expected result: x10 = 15

.section .text
.globl _start

_start:
    # Initialize values
    addi x10, x0, 5      # x10 = 5
    addi x11, x0, 10     # x11 = 10

    # Add them
    add x12, x10, x11    # x12 = 5 + 10 = 15

    # Move result to x10 for checking
    addi x10, x12, 0     # x10 = x12 = 15

    # End test
    ebreak
