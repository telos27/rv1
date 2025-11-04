# RV64I LD Only Test
# Pre-store value using SW, then load with LD
# Use .option norvc to disable compressed instructions

.section .text
.globl _start

.option norvc  # Disable compressed instructions

_start:
    li      a0, 0x2000              # Address
    li      a1, 0x77                # Value
    sw      a1, 0(a0)               # Store word (32-bit instruction)
    ld      a2, 0(a0)               # Load doubleword (32-bit instruction)
    mv      a0, a2                  # Move result to a0
    nop                              # Give time for MV to writeback
    nop
    ebreak
