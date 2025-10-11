# Minimal NOP test to verify pipeline still works
.section .text
.globl _start

_start:
    li a0, 0x600D
    nop
    nop
    nop
    nop
    ebreak
