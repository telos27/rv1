# Test LR instruction only
.section .text
.globl _start

_start:
    lui     a0, 0x1000      # a0 = 0x1000
    li      t0, 42          # t0 = 42
    sw      t0, 0(a0)       # M[0x1000] = 42
    lr.w    t1, (a0)        # t1 = M[0x1000], reserve
    li      t2, 42
    bne     t1, t2, fail

pass:
    li      a0, 0
    ebreak

fail:
    li      a0, 1
    ebreak
