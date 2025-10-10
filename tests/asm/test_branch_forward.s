# Test forwarding after branch
# This tests if register values are correct after branching back

.section .text
.globl _start

_start:
    li x1, 0                # Counter
    li x2, 0xDEAD           # x2 = initial value

loop:
    # In each iteration, we set x2 to a new value
    # and immediately use it
    addi x1, x1, 1           # x1++

    li x2, 0x1111           # Set x2 to 0x1111
    add x3, x2, x2          # x3 = x2 + x2 = 0x2222

    li x4, 2
    bne x1, x4, loop        # Loop twice

    # After 2 iterations:
    # x1 should be 2
    # x2 should be 0x1111
    # x3 should be 0x2222

    # Verify
    li x10, 0x1111
    bne x2, x10, fail

    li x10, 0x2222
    bne x3, x10, fail

    li x10, 42
    j end

fail:
    li x10, 0xBAD

end:
    ecall
