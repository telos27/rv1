# Test misaligned memory access
# Tests that hardware supports misaligned loads/stores

.section .text
.globl _start

_start:
    # Initialize data memory with known pattern
    # Address 0x1000: 00 01 02 03 04 05 06 07
    li      t0, 0x1000
    li      t1, 0x03020100    # Little-endian: bytes 00,01,02,03
    sw      t1, 0(t0)
    li      t1, 0x07060504    # Little-endian: bytes 04,05,06,07
    sw      t1, 4(t0)

    # Test 1: Misaligned halfword load at 0x1001
    # Should load bytes [02, 01] = 0x0201 = 513
    lh      t2, 1(t0)
    li      t3, 513
    bne     t2, t3, fail

    # Test 2: Misaligned word load at 0x1001
    # Should load bytes [04, 03, 02, 01] = 0x04030201
    lw      t2, 1(t0)
    li      t3, 0x04030201
    bne     t2, t3, fail

    # Test 3: Misaligned halfword store at 0x1009
    li      t0, 0x1008
    li      t1, 0xBBAA       # Will store at 0x1009
    sh      t1, 1(t0)
    lh      t2, 1(t0)
    bne     t2, t1, fail

    # Success
    li      a0, 42
    j       done

fail:
    li      a0, 1

done:
    # Write result to x10 and stop
    nop
    nop
    nop
