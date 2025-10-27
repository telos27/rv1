# test_clint_basic.s - Basic CLINT Register Access Test
# Verifies MTIME increments and MTIMECMP is writable
# Author: RV1 Project - Phase 1.5 Debug
# Date: 2025-10-27

.section .text
.global _start

_start:
    # Test 1: Read MTIME (should be non-zero after a few cycles)
    li      t0, 0x0200BFF8          # MTIME address
    lw      t1, 0(t0)               # Read lower 32 bits
    lw      t2, 4(t0)               # Read upper 32 bits

    # MTIME should be > 0 after several cycles
    bnez    t1, 1f                  # If lower bits non-zero, good
    bnez    t2, 1f                  # If upper bits non-zero, good
    j       test_fail               # Both zero = bad

1:  # Test 2: Write and read back MTIMECMP
    li      t0, 0x02004000          # MTIMECMP address
    li      t1, 0x12345678          # Test value lower
    li      t2, 0x9ABCDEF0          # Test value upper
    sw      t1, 0(t0)               # Write lower 32 bits
    sw      t2, 4(t0)               # Write upper 32 bits

    lw      t3, 0(t0)               # Read back lower
    lw      t4, 4(t0)               # Read back upper

    bne     t1, t3, test_fail       # Check lower matches
    bne     t2, t4, test_fail       # Check upper matches

    # Test 3: Write and read MSIP
    li      t0, 0x02000000          # MSIP address
    li      t1, 0x00000001          # Set bit 0
    sw      t1, 0(t0)               # Write MSIP

    lw      t2, 0(t0)               # Read back
    andi    t2, t2, 0x1             # Mask to bit 0
    bne     t1, t2, test_fail       # Should match

test_pass:
    li      a0, 0                   # Exit code 0
    ebreak

test_fail:
    li      a0, 1                   # Exit code 1
    ebreak
