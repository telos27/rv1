# Test MULHU bug found in FreeRTOS
# Bug: MULHU 1, 84 returns 10 instead of 0
#
# Expected behavior:
#   1 * 84 = 84 (fits in 32 bits)
#   Upper 32 bits should be 0
#
# Actual behavior:
#   MULHU returns 10 (0x0A) - WRONG!

.section .text
.globl _start

_start:
    # Test case 1: MULHU 1, 84 (the exact case from FreeRTOS)
    li      a0, 1
    li      a1, 84
    mulhu   a2, a0, a1      # a2 = upper 32 bits of (1 * 84)

    # Expected: a2 = 0
    # Actual: a2 = ??? (debug this!)

    # Store result in memory for debugging
    li      t0, 0x80001000
    sw      a0, 0(t0)       # Store operand 1
    sw      a1, 4(t0)       # Store operand 2
    sw      a2, 8(t0)       # Store MULHU result

    li      a3, 0           # Expected result
    bne     a2, a3, fail_test1

    # Test case 2: MULHU 2, 42 (also = 84, should also give 0)
    li      a0, 2
    li      a1, 42
    mulhu   a2, a0, a1

    li      a3, 0
    bne     a2, a3, fail_test2

    # Test case 3: MULHU with actual overflow
    # 0x10000 * 0x10000 = 0x100000000 (upper = 1)
    li      a0, 0x10000
    li      a1, 0x10000
    mulhu   a2, a0, a1

    li      a3, 1           # Expected: upper 32 bits = 1
    bne     a2, a3, fail_test3

    # Test case 4: MULHU 0xFFFFFFFF * 0xFFFFFFFF
    # Result: 0xFFFFFFFE00000001, upper = 0xFFFFFFFE
    li      a0, -1          # 0xFFFFFFFF
    li      a1, -1          # 0xFFFFFFFF
    mulhu   a2, a0, a1

    li      a3, 0xFFFFFFFE
    bne     a2, a3, fail_test4

pass:
    li      a0, 0           # Test PASS
    li      a7, 93          # exit syscall
    ecall

fail_test1:
    li      a0, 1           # Test 1 FAILED
    li      a7, 93
    ecall

fail_test2:
    li      a0, 2           # Test 2 FAILED
    li      a7, 93
    ecall

fail_test3:
    li      a0, 3           # Test 3 FAILED
    li      a7, 93
    ecall

fail_test4:
    li      a0, 4           # Test 4 FAILED
    li      a7, 93
    ecall
