# Test: Simple MRET Test
# Just test if MRET jumps to MEPC

.section .text
.globl _start

_start:
    # Set MEPC to target address
    la      t0, target_location
    csrw    mepc, t0

    # Set some marker before MRET
    li      t1, 0x11111111

    # Execute MRET
    mret

    # Should NOT reach here
    li      t2, 0xBADBAD00
    j       fail

target_location:
    # Should reach here after MRET
    li      t2, 0xC0FFEE00
    j       pass

pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

.align 4
