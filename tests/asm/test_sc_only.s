# Test SC instruction only (should fail since no prior LR)
.section .text
.globl _start

_start:
    lui     a0, 0x1000      # a0 = 0x1000
    li      t0, 42          # t0 = 42
    sw      t0, 0(a0)       # M[0x1000] = 42
    li      t1, 99          # t1 = 99
    sc.w    t2, t1, (a0)    # Try SC (should fail, t2=1)
    li      t3, 1           # Expected: SC fails
    bne     t2, t3, fail    # If t2 != 1, test fails

pass:
    li      a0, 0
    ebreak

fail:
    li      a0, 1
    ebreak
