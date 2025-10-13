# Simple CSR test - just test one CSR
.section .text
.globl _start

_start:
    # Test 1: Write and read MSCRATCH
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, fail

    # Success
    li      a0, 1
    ebreak

fail:
    li      a0, 0
    ebreak
