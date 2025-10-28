# Simple MULHU test - just compute and store result
# Test: MULHU 1, 84 (from FreeRTOS bug)

.section .text
.globl _start

_start:
    # Compute MULHU 1, 84
    li      a0, 1
    li      a1, 84
    mulhu   a2, a0, a1      # a2 = upper 32 bits of (1 * 84)

    # Also compute MUL for comparison
    mul     a3, a0, a1      # a3 = lower 32 bits of (1 * 84)

    # Store everything in first 16 bytes of DMEM
    li      t0, 0x80000000
    sw      a0, 0(t0)       # [0x80000000] = operand 1 = 1
    sw      a1, 4(t0)       # [0x80000004] = operand 2 = 84
    sw      a3, 8(t0)       # [0x80000008] = MUL result (lower) = 84
    sw      a2, 12(t0)      # [0x8000000C] = MULHU result (upper) = ???

    # Exit with result in a0
    mv      a0, a2          # Return MULHU result
    li      a7, 93
    ecall
