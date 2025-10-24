# Test writing to x28
.option norvc

.section .text
.globl _start

_start:
    li t0, 0xDEADBEEF
    mv x28, t0
    ebreak
