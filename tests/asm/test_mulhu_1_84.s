# Test MULHU with exact values from FreeRTOS failure
# Test: MULHU 1, 84
# Expected: 0 (since 1*84 = 84, fits in 32 bits)
# FreeRTOS got: 10 (0x0A)

.section .text
.globl _start

_start:
    # Initialize test number
    li      gp, 0

test_1:
    # Test 1: MULHU 1, 84 (exact FreeRTOS case)
    li      a0, 1
    li      a1, 84
    mulhu   a2, a0, a1

    # Expected result: 0
    li      a3, 0
    bne     a2, a3, fail

    # Increment test counter
    addi    gp, gp, 1

test_2:
    # Test 2: Also compute MUL to verify lower bits
    li      a0, 1
    li      a1, 84
    mul     a2, a0, a1

    # Expected result: 84
    li      a3, 84
    bne     a2, a3, fail

    # Increment test counter
    addi    gp, gp, 1

test_3:
    # Test 3: MULHU with reversed operands
    li      a0, 84
    li      a1, 1
    mulhu   a2, a0, a1

    # Expected result: 0
    li      a3, 0
    bne     a2, a3, fail

    # Increment test counter
    addi    gp, gp, 1

pass:
    # All tests passed
    li      a0, 0
    li      a7, 93
    ecall

fail:
    # Failed - gp contains which test failed (0, 1, or 2)
    # Move gp to a0 for return value
    mv      a0, gp
    addi    a0, a0, 1  # Return test number (1-based)
    li      a7, 93
    ecall
