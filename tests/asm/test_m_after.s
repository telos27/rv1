# Test instructions after MUL
.section .text
.globl _start

_start:
    li a0, 5
    li a1, 10
    mul a2, a0, a1          # a2 = 50

    # These should execute after MUL completes
    li a3, 0xAAAA           # Marker 1
    li a4, 0xBBBB           # Marker 2
    li a5, 0xCCCC           # Marker 3

    li a0, 0x600D
    nop
    nop
    nop
    nop
    ebreak
