# Test RV64 unaligned load handling
# Tests byte loads from different offsets

.section .text
.globl _start

_start:
    # Initialize test data in memory
    li      t0, 0x80002000      # Base address

    # Write test pattern: 0xff 0x00 0xf0 0x0f
    li      t1, 0xff
    sb      t1, 0(t0)
    li      t1, 0x00
    sb      t1, 1(t0)
    li      t1, 0xf0
    sb      t1, 2(t0)
    li      t1, 0x0f
    sb      t1, 3(t0)

    # Test 1: Load byte from offset 0 (0xff)
    lb      a0, 0(t0)
    li      a1, 0xffffffffffffffff  # Expected: sign-extended 0xff
    bne     a0, a1, fail

    # Test 2: Load byte from offset 1 (0x00)
    lb      a0, 1(t0)
    li      a1, 0x0000000000000000  # Expected: sign-extended 0x00
    bne     a0, a1, fail

    # Test 3: Load byte from offset 2 (0xf0)
    lb      a0, 2(t0)
    li      a1, 0xfffffffffffffff0  # Expected: sign-extended 0xf0
    bne     a0, a1, fail

    # Test 4: Load byte from offset 3 (0x0f) - THIS IS WHERE OFFICIAL TEST FAILS
    lb      a0, 3(t0)
    li      a1, 0x000000000000000f  # Expected: sign-extended 0x0f (positive)
    bne     a0, a1, fail

    # Test 5: Load byte unsigned from offset 3
    lbu     a0, 3(t0)
    li      a1, 0x000000000000000f  # Expected: zero-extended 0x0f
    bne     a0, a1, fail

    # Test 6: Load halfword from offset 2 (0x0ff0 little-endian)
    lh      a0, 2(t0)
    li      a1, 0x0000000000000ff0  # Expected: 0x0f | (0xf0 << 8)
    bne     a0, a1, fail

    # All tests passed
    li      a0, 1
    j       pass

fail:
    li      a0, 0

pass:
    # ECALL to exit
    li      a7, 93      # exit syscall
    ecall

    # Infinite loop (shouldn't reach here)
1:  j       1b
