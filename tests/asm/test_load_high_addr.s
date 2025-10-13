# Test loading from high address space (0x80000000+)
# This mimics the official compliance test memory layout

.section .text
.globl _start

_start:
    # First store a known value to high address
    lui  x10, 0x80002       # x10 = 0x80002000
    li   x11, 0x12345678    # x11 = 0x12345678
    sw   x11, 0(x10)        # mem[0x80002000] = 0x12345678

    # Now load it back
    lw   x12, 0(x10)        # x12 = mem[0x80002000]

    # Check if they match
    bne  x11, x12, fail

success:
    li   x28, 0xDEADBEEF
    ebreak

fail:
    # Store loaded value in x28 for debugging
    mv   x28, x11
    ebreak
