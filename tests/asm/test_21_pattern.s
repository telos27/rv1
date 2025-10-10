# Replicate test 21 pattern from compliance
.section .text
.globl _start

_start:
    li x3, 21           # Test number
    li x4, 0            # Loop counter

loop:
    lui x2, 0xf0f1       # sp = 0xf0f10000
    addi x2, x2, -241    # sp = 0xf0f0f0f
    nop
    lui x1, 0xff010      # ra = 0xff010000
    addi x1, x1, -256    # ra = 0xff00ff00
    and x14, x1, x2      # a4 = ra & sp

    addi x4, x4, 1
    li x5, 2
    bne x4, x5, loop

    # Expected: x14 = 0xf000f00
    lui x10, 0xf001
    addi x10, x10, -256
    bne x14, x10, fail

    li x10, 42
    j end

fail:
    li x10, 0xBAD

end:
    ecall
