# Test: Simple CSR Read/Write - mscratch only
# Purpose: Minimal test to verify CSR operations work
# Expected: mscratch should read back written value

.section .text
.globl _start

_start:
    # Write to mscratch
    li t0, 0xABCD1234
    csrw mscratch, t0

    # Read from mscratch
    csrr t1, mscratch

    # Store in a0 for verification
    mv a0, t1

    # Exit
    ebreak

.section .data
