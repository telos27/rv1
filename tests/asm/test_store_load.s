# Test simple store and load
.section .text
.globl _start

_start:
    lui     a0, 0x1000      # a0 = 0x1000
    li      t0, 99          # t0 = 99
    sw      t0, 0(a0)       # M[0x1000] = 99
    lw      t1, 0(a0)       # t1 = M[0x1000]
    li      t2, 99
    bne     t1, t2, fail

pass:
    li      a0, 0
    j       done

fail:
    li      a0, 1

done:
    ebreak
