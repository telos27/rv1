# Replicate the exact pattern from compliance test 19
# This test mimics the loop structure that's failing

.section .text
.globl _start

_start:
    # Test 19 pattern
    li x3, 19                # gp = 19 (test number)
    li x4, 0                 # tp = 0 (loop counter)

loop:
    lui x2, 0xf0f0f          # sp = 0xf0f0f000
    addi x2, x2, 240         # sp = 0xf0f0f0f0
    lui x1, 0xff01           # ra = 0xff010000
    addi x1, x1, -16         # ra = 0x0ff00ff0
    nop
    and x14, x1, x2          # a4 = ra & sp = 0x00f000f0

    addi x4, x4, 1           # tp++
    li x5, 2                 # t0 = 2
    bne x4, x5, loop         # if tp != 2, loop

    # Expected results:
    # x1 = 0x0ff00ff0
    # x2 = 0xf0f0f0f0
    # x14 = 0x00f000f0

    # Verification
    lui x10, 0x00f00         # Expected x14 value
    addi x10, x10, 0xf0      # x10 = 0x00f000f0
    bne x14, x10, fail

    # Success
    li x10, 42               # Success marker
    j end

fail:
    li x10, 0xBAD            # Failure marker

end:
    ecall
