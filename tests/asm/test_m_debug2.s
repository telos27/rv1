# Debug M extension - Check if MUL completes
.section .text
.globl _start

_start:
    # Simple test - just one MUL
    li a0, 5
    li a1, 10
    mul a2, a0, a1      # a2 = 5 * 10 = 50

    # Check if we get here
    li a3, 0x1234       # Marker: reached after MUL

    # Exit
    li a0, 0x600D
    nop
    nop
    nop
    nop
    ebreak
