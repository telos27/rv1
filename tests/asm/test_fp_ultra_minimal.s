# Ultra Minimal Test - No FP, just to verify basic execution
.section .text
.globl _start

_start:
    li x10, 0x12345678
    li x11, 0xABCDEF00
    add x12, x10, x11
    ebreak
