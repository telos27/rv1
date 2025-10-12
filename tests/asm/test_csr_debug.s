# Test: CSR Debug - Check what CSR read returns
# Store intermediate values in different registers to see what's happening

.section .text
.globl _start

_start:
    # Store a known pattern in t0
    li      t0, 0x12345678

    # Write to mscratch
    csrw    mscratch, t0

    # Read from mscratch into t1
    csrr    t1, mscratch

    # Copy to more registers for visibility
    mv      t2, t0          # t2 should be 0x12345678
    mv      t3, t1          # t3 should be 0x12345678 if CSR works

    # Also test another CSR - mstatus (should be readable)
    csrr    t4, mstatus

    # Set marker and break
    li      t5, 0xC0FFEE00
    mv      x28, t5
    ebreak

.align 4
