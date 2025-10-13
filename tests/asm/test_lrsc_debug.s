# Test LR/SC basic operation
# Minimal test to debug the timeout issue

.section .text
.globl _start

_start:
    # Initialize address
    la      a0, test_var        # a0 = address of test variable
    li      t0, 0x12345678
    sw      t0, 0(a0)           # Store initial value

    # Test 1: Simple LR/SC that should succeed
test_simple:
    lr.w    t1, (a0)            # Load reserved
    addi    t1, t1, 1           # Increment
    sc.w    t2, t1, (a0)        # Store conditional

    # Check result
    bnez    t2, fail            # t2 should be 0 (success)

    # Verify the value was written
    lw      t3, 0(a0)
    li      t4, 0x12345679      # Expected value
    bne     t3, t4, fail

pass:
    li      a0, 0               # Success
    j       exit

fail:
    li      a0, 1               # Failure
    j       exit

exit:
    # Write to tohost to signal completion
    la      t0, tohost
    li      t1, 1
    sw      t1, 0(t0)
    j       exit

.section .data
.align 4
test_var:
    .word   0

.section .tohost
.align 4
.globl tohost
tohost:
    .word 0
.globl fromhost
fromhost:
    .word 0
