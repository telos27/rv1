# Test for debugging JAL to halfword-aligned address
# This mimics the rv32uc-p-rvc test_2 pattern

.section .text
.globl _start

_start:
    # Reset vector - jump past trap handler
    j reset_vector

trap_vector:
    # Trap handler - jump to completion
    lui   t5, 0x80003
    sw    gp, 0(t5)        # Write to tohost
    sw    zero, 4(t5)       # Clear tohost+4
    j     trap_vector       # Infinite loop (test done)

reset_vector:
    # Initialize registers
    li    gp, 0
    li    a1, 666           # 0x29a

test_2:
    li    gp, 2             # Test number
    j     target_at_1ffe    # Jump to halfword-aligned target

    # Padding to make target land at +0x1e66 bytes
    .space 0x1e66 - (target_at_1ffe - test_2)

target_at_1ffe:
    addi  a1, a1, 1         # a1 should become 667
    li    t2, 667
    bne   a1, t2, fail
    j     pass

fail:
    li    gp, 0x1337        # Failure marker
    j     trap_vector

pass:
    li    gp, 1             # Success
    j     trap_vector

.align 4
