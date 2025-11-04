# RV64I Simple LD Test
# Just test a single LD instruction

.section .text
.globl _start

_start:
    # Set up address
    li      t0, 0x80002000          # Use full 32-bit address assembly

    # Pre-store a known value
    li      t1, 0x12345678
    sw      t1, 0(t0)               # Store word first (SW works in RV64)

    # Test LD instruction
    ld      t2, 0(t0)               # Load doubleword

    # Check result (lower 32 bits should match)
    li      t3, 0x12345678
    bne     t2, t3, test_fail

test_pass:
    li      a0, 1                   # Success
    j       done

test_fail:
    li      a0, 0                   # Failure

done:
    j       done
