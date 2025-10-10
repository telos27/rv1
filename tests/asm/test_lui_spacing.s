# Test LUI with different amounts of spacing before ADDI

.section .text
.globl _start

_start:
    # Test 1: No spacing
    lui x1, 0xff010
    addi x2, x1, -256    # x2 should be 0xff00ff00

    # Test 2: 1 NOP
    lui x3, 0xff010
    nop
    addi x4, x3, -256    # x4 should be 0xff00ff00

    # Test 3: 2 NOPs
    lui x5, 0xff010
    nop
    nop
    addi x6, x5, -256    # x6 should be 0xff00ff00

    # Test 4: 3 NOPs
    lui x7, 0xff010
    nop
    nop
    nop
    addi x8, x7, -256    # x8 should be 0xff00ff00

    # Verify all are equal
    li x10, 0xff00ff00
    bne x2, x10, fail
    bne x4, x10, fail
    bne x6, x10, fail
    bne x8, x10, fail

    li x10, 42
    j end

fail:
    li x10, 0xBAD

end:
    ecall
