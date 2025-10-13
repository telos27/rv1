# Simple STVEC test with NOPs to avoid hazards
.section .text
.globl _start

_start:
    # Test STVEC write/read
    lui     t0, 0x80001
    nop
    nop
    csrw    stvec, t0
    nop
    nop
    csrr    t1, stvec
    nop
    nop
    lui     t2, 0x80001
    nop
    nop
    bne     t1, t2, fail

    # Success
    li      a0, 1
    ebreak

fail:
    li      a0, 0
    ebreak
