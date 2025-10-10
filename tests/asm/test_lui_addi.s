# Minimal test for LUI followed by ADDI (same register)
# This is the simplest case that should expose the bug

.section .text
.globl _start

_start:
    # Simple LUI + ADDI chain
    lui x2, 0xf0f0f          # x2 = 0xf0f0f000
    addi x2, x2, 240         # x2 = x2 + 240 = 0xf0f0f0f0

    # Store result for verification
    lui x10, 0xf0f0f
    addi x10, x10, 0x0f0     # x10 = 0xf0f0f0f0 (expected value)

    # Check if x2 == x10
    bne x2, x10, fail

    # Success
    li x11, 42
    j end

fail:
    li x11, 0xBAD

end:
    ecall
