.section .text
.globl _start
_start:
    li t0, 0x12345678
    li t1, 0x80001000
    sw t0, 0(t1)
    .rept 30
    nop
    .endr
    lw t2, 0(t1)
    bne t0, t2, fail
    li x28, 0
    ebreak
fail:
    li x28, 0xdeaddead
    ebreak
