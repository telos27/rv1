# Test division by zero behavior
# According to RISC-V spec:
#   DIVU x/0 = 0xFFFFFFFF
#   REMU x/0 = x

.section .text
.globl _start

_start:
    # Test 1: divu 1/0 should return 0xFFFFFFFF
    li x1, 1
    li x2, 0
    divu x3, x1, x2
    li x4, -1        # 0xFFFFFFFF
    bne x3, x4, fail

    # Test 2: remu 1/0 should return 1
    li x5, 1
    li x6, 0
    remu x7, x5, x6
    li x8, 1
    bne x7, x8, fail

    # Test 3: remu 42/0 should return 42
    li x9, 42
    li x10, 0
    remu x11, x9, x10
    li x12, 42
    bne x11, x12, fail

pass:
    li x3, 1        # Test passed
    ecall

fail:
    li x3, 0        # Test failed
    ecall
