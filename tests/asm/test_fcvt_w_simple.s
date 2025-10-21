# Simple test for fcvt.w.s with 0.9
# Expected: result=0, fflags=0x01 (NX)

.section .text
.globl _start

_start:
    # Load 0.9 into f0
    lui t0, 0x3f666          # Upper bits of 0x3f666666 (0.9 in float)
    addi t0, t0, 0x666       # Lower bits
    fmv.w.x f0, t0           # Move to FP register

    # Convert to integer
    fcvt.w.s a0, f0, rtz     # Should give 0

    # Read flags
    frflags a1               # Should give 0x01 (NX)

    # Check result
    li t1, 0
    bne a0, t1, fail

    # Check flags
    li t2, 0x01
    bne a1, t2, fail

pass:
    li a0, 0
    li a7, 93                # exit syscall
    ecall

fail:
    li a0, 1
    li a7, 93
    ecall
