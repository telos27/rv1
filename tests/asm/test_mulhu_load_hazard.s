# Test: MULHU with load-use hazard
# Reproduces the exact sequence from FreeRTOS that causes MULHU bug
# Expected behavior: LW loads 84, MULHU 1×84 = 0 (high word)
# Buggy behavior: MULHU returns 10 instead of 0

.section .text
.globl _start
.org 0

_start:
    # Initialize test number
    li   gp, 0

    # Initialize test data in memory
    li   t0, 0x80000000      # DMEM base
    li   t1, 84              # Value to store (0x54)
    sw   t1, 64(t0)          # Store 84 at offset 64

    # Set up for MULHU test
    li   a5, 1               # First operand = 1

    # This is the exact sequence from FreeRTOS:
    # LW immediately before MULHU creates load-use hazard
    lw   a4, 64(t0)          # Load 84 into a4 (load-use hazard)
    mulhu a5, a5, a4         # MULHU 1 × 84 → a5 (should be 0)

    # Check result
    li   t2, 0               # Expected result = 0
    bne  a5, t2, fail        # If a5 != 0, test failed

    # Test passed
    addi gp, gp, 1

pass:
    li   a0, 0               # Success code
    li   a7, 93              # Exit syscall
    ecall

fail:
    # gp contains which test failed
    mv   a0, gp
    addi a0, a0, 1           # Return test number (1-based)
    li   a7, 93              # Exit syscall
    ecall
