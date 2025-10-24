# Test EBREAK timing - when do register writes complete?
.option norvc

.section .text
.globl _start

_start:
    # Test 1: Write to x28 with NOPs before EBREAK
    li t0, 0xDEADBEEF
    mv x28, t0
    nop
    nop
    nop
    nop
    nop
    ebreak
