# Test: Enter S-mode
# Simple test to verify we can enter S-mode via MRET

.section .text
.globl _start

_start:
    # Set MSTATUS.MPP = 01 (S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF        # Mask to clear MPP[12:11]
    and     t0, t0, t1
    li      t1, 0x00000800        # MPP = 01 (S-mode)
    or      t0, t0, t1
    csrw    mstatus, t0

    # Verify MPP is set correctly
    csrr    t2, mstatus
    srli    t2, t2, 11
    andi    t2, t2, 0x3           # Extract MPP bits
    li      t3, 0x1               # Should be 01
    bne     t2, t3, test_fail

    # Set MEPC to S-mode code
    la      t0, s_mode_code
    csrw    mepc, t0

    # Store marker before MRET
    li      t4, 0x11111111

    # Enter S-mode
    mret

s_mode_code:
    # Store marker to show we reached S-mode
    li      t5, 0x22222222

    # Try to access S-mode CSR (should work)
    li      t0, 0xABCDABCD
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    j       test_pass

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
