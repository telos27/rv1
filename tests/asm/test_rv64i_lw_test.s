# RV64I LW Test
# Test if LW works (32-bit load)

.section .text
.globl _start

.option norvc

_start:
    li      a0, 0x2000              # Address
    li      a1, 0x77                # Value
    sw      a1, 0(a0)               # Store word
    lw      a2, 0(a0)               # Load word (should work)
    mv      a0, a2                  # Move result to a0
    ebreak
