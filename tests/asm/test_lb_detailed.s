# Detailed LB (load byte) test
# Test various byte load scenarios

.section .text
.globl _start

_start:
    # Set up test data
    li x1, 0x1000        # Base address
    li x2, 0x12345678    # Test pattern
    sw x2, 0(x1)         # Store at 0x1000

    # Test 1: Load byte 0 (0x78, sign-extended to 0x00000078)
    lb x3, 0(x1)
    li x10, 0x00000078
    bne x3, x10, fail1

    # Test 2: Load byte 1 (0x56, sign-extended to 0x00000056)
    lb x4, 1(x1)
    li x10, 0x00000056
    bne x4, x10, fail2

    # Test 3: Load byte 2 (0x34, sign-extended to 0x00000034)
    lb x5, 2(x1)
    li x10, 0x00000034
    bne x5, x10, fail3

    # Test 4: Load byte 3 (0x12, sign-extended to 0x00000012)
    lb x6, 3(x1)
    li x10, 0x00000012
    bne x6, x10, fail4

    # Test 5: Load negative byte (0xFF = -1, sign-extended to 0xFFFFFFFF)
    li x2, 0xFF
    sb x2, 4(x1)
    lb x7, 4(x1)
    li x10, 0xFFFFFFFF
    bne x7, x10, fail5

    # Success
    li x10, 42
    j end

fail1:
    li x10, 1
    j end
fail2:
    li x10, 2
    j end
fail3:
    li x10, 3
    j end
fail4:
    li x10, 4
    j end
fail5:
    li x10, 5
    j end

end:
    ecall
