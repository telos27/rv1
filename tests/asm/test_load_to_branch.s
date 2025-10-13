# Minimal test for load-to-branch hazard
# This reproduces the exact failure pattern from official tests

.section .text
.globl _start

_start:
    # Store known value
    li   x10, 0x1000        # x10 = address
    li   x11, 0xAAAABBBB    # x11 = test value
    sw   x11, 0(x10)        # Store it

    # Now do load followed by branch (with exactly 2 instructions in between like official test)
    lw   x12, 0(x10)        # Load into x12
    lui  x13, 0xAAAAB       # Instruction 1
    addi x13, x13, 0x7BB    # Instruction 2 (gets us to 0xBBB with sign extension)
    bne  x11, x12, fail     # Compare loaded vs stored - should be EQUAL!

success:
    li   x28, 0xDEADBEEF
    ebreak

fail:
    li   x28, 0xDEADDEAD
    ebreak
