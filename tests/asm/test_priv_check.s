# Test: Check Privilege Mode
# See if we can read current privilege mode

.section .text
.globl _start

_start:
    # Read initial mstatus
    csrr    t0, mstatus

    # Try to set MPP to S-mode
    li      t1, 0xFFFFE7FF
    and     t0, t0, t1
    li      t1, 0x00000800
    or      t0, t0, t1
    csrw    mstatus, t0

    # Read back mstatus
    csrr    t2, mstatus

    # Extract MPP bits [12:11]
    srli    t3, t2, 11
    andi    t3, t3, 0x3

    # t3 should now contain MPP value (should be 1 for S-mode)
    # Store all values for inspection
    # t0 = modified mstatus value
    # t2 = read-back mstatus
    # t3 = extracted MPP bits

    # Set MEPC to target
    la      t4, after_mret
    csrw    mepc, t4

    # Do MRET
    mret

after_mret:
    # Store marker showing we got here
    li      t5, 0x99999999

    # Try accessing sscratch (should work in S-mode)
    li      t6, 0x77777777
    csrw    sscratch, t6

    # SUCCESS
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
