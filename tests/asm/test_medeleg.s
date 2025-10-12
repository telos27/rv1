# Test: MEDELEG CSR Test
# Test delegation CSR specifically

.section .text
.globl _start

_start:
    # Test 1: Write and read med eleg
    li      t0, 0x00000555
    csrw    medeleg, t0
    csrr    t1, medeleg

    # Store for visibility
    mv      t2, t0          # Expected value
    mv      t3, t1          # Actual value from CSR

    # Test 2: Also test mideleg
    li      t4, 0x00000AAA
    csrw    mideleg, t4
    csrr    t5, mideleg

    # Check results
    bne     t0, t1, fail
    bne     t4, t5, fail

pass:
    li      a0, 0xDEADBEEF
    mv      x28, a0
    ebreak

fail:
    li      a0, 0xDEADDEAD
    mv      x28, a0
    ebreak

.align 4
