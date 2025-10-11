# M test with NOPs after MUL
.section .text
.globl _start

_start:
    li a0, 5
    li a1, 10
    mul a2, a0, a1      # a2 = 5 * 10 = 50
    nop
    nop
    nop
    li a0, 0x600D       # Pass indicator
    nop
    nop
    nop
    nop
    ebreak
