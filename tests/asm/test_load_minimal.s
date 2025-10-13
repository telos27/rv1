# Minimal load test to debug pipeline bug
# This test stores a value to memory, then loads it back
# Expected: Load should return the stored value

.section .text
.globl _start

_start:
    # Initialize data memory address
    li   x10, 0x1000        # x10 = 0x1000 (data address)

    # Store a known value
    li   x11, 0xDEADBEEF    # x11 = 0xDEADBEEF
    sw   x11, 0(x10)        # mem[0x1000] = 0xDEADBEEF

    # Load it back
    lw   x12, 0(x10)        # x12 = mem[0x1000]

    # Check if values match
    bne  x11, x12, fail

success:
    # Set success marker
    li   x28, 0xDEADBEEF
    ebreak

fail:
    # Set failure marker
    li   x28, 0xDEADDEAD
    ebreak
