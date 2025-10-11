# Test LR/SC back-to-back
.section .text
.globl _start

_start:
    lui     a0, 0x1000      # a0 = 0x1000
    li      t0, 42          # t0 = 42
    sw      t0, 0(a0)       # M[0x1000] = 42
    lr.w    t1, (a0)        # LR
    sc.w    t2, t0, (a0)    # SC immediately after (store same value)
    # t2 should be 0 (success)
    bnez    t2, fail

    # Verify value
    lw      t3, 0(a0)
    li      t4, 42
    bne     t3, t4, fail

pass:
    ebreak

fail:
    nop
    ebreak
