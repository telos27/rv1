# RV64I Minimal SD/LD Test
# No branches, just store and load

.section .text
.globl _start

_start:
    # Use a simple register-based address
    li      a0, 0x2000              # Simple address (will be 0x80002000)
    li      a1, 0x42                # Test value

    # SD and LD
    sd      a1, 0(a0)               # Store doubleword
    ld      a2, 0(a0)               # Load doubleword

    # Set result in a0
    mv      a0, a2                  # Move result to a0
    nop                              # Give time for writeback
    nop

    # EBREAK to end test
    ebreak
