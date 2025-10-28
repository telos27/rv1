# Test MULHU 10, 16
# Product = 160 = 0xA0, fits in 32 bits
# Expected high word = 0

.section .text
.globl _start

_start:
    # Initialize test number
    li      gp, 0

test_1:
    # Test: MULHU 10, 16
    li      a0, 10
    li      a1, 16
    mulhu   a2, a0, a1

    # Expected result: 0
    li      a3, 0
    bne     a2, a3, fail

    # Increment test counter
    addi    gp, gp, 1

test_2:
    # Verify with MUL (low word)
    li      a0, 10
    li      a1, 16
    mul     a2, a0, a1

    # Expected result: 160 (0xA0)
    li      a3, 160
    bne     a2, a3, fail

    # Increment test counter
    addi    gp, gp, 1

pass:
    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    # Failed - gp contains which test failed
    mv      a0, gp
    addi    a0, a0, 1
    li      a7, 93
    ecall
