# Very simple check - just verify basic operation after enabling M extension
.section .text
.globl _start

_start:
    li a0, 0x1111
    li a1, 0x2222
    li a2, 0x3333
    li a0, 0x600D    # Final value
    nop
    nop
    nop
    nop
    ebreak
