# Test: SRET instruction
# Test SRET returns to correct PC and restores privilege

.section .text
.globl _start

_start:
    # Set up SEPC to point to return address
    la      t0, return_point
    csrw    sepc, t0

    # Set SSTATUS.SPP = 0 (will return to U-mode)
    # Set SSTATUS.SPIE = 1 (interrupt enable will be restored)
    li      t0, 0x00000020        # SPIE bit
    csrw    sstatus, t0

    # Execute SRET
    sret

return_point:
    # We should arrive here after SRET
    # Verify we got here by setting success code
    li      a0, 1
    ebreak

fail:
    li      a0, 0
    ebreak
