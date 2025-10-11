# Minimal LR/SC Test
# Tests basic load-reserved / store-conditional

.section .text
.globl _start

_start:
    # Initialize memory location
    lui     a0, 0x1000          # a0 = 0x1000 (base address)
    li      t0, 42              # t0 = 42
    sw      t0, 0(a0)           # M[0x1000] = 42

    # LR.W: Load reserved
    lr.w    t1, (a0)            # t1 = M[0x1000], reserve 0x1000

    # Verify loaded value
    li      t2, 42
    bne     t1, t2, fail        # If t1 != 42, fail

    # Increment value
    addi    t1, t1, 1           # t1 = 43

    # SC.W: Store conditional
    sc.w    t3, t1, (a0)        # Try to store 43 to M[0x1000], t3 = success flag

    # Verify SC succeeded (t3 should be 0)
    bnez    t3, fail            # If t3 != 0, SC failed

    # Verify stored value
    lw      t4, 0(a0)           # Load value back
    li      t5, 43
    bne     t4, t5, fail        # If t4 != 43, fail

pass:
    li      a0, 0               # Return 0 (success)
    j       done

fail:
    li      a0, 1               # Return 1 (failure)

done:
    # Infinite loop
    j       done
