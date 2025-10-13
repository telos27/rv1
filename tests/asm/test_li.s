# Test LI pseudo-instruction
.section .text
.globl _start

_start:
    # Test loading a 32-bit immediate
    li      t0, 0x12345678
    li      t1, 0x12345678
    bne     t0, t1, fail

    # Success
    li      a0, 1
    ebreak

fail:
    li      a0, 0
    ebreak
