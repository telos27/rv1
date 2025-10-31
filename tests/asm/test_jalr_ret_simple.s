# test_jalr_ret_simple.s - Simple JALR/RET test
# Tests basic function call and return

.section .text
.globl _start

_start:
    # Initialize ra to a known bad value
    li ra, 0xDEADBEEF

    # Initialize test counter
    li a0, 0

    # Call function that will increment a0
    jal ra, test_func

    # If we get here, test passed
    # a0 should be 1
    li a1, 1
    beq a0, a1, pass

fail:
    li a0, 0  # Test failed
    j end

pass:
    li a0, 1  # Test passed
    j end

test_func:
    # Increment a0
    addi a0, a0, 1

    # Return (jalr x0, ra, 0)
    ret

end:
    # Write result to test status address
    li t0, 0x80001000
    sw a0, 0(t0)

    # Infinite loop
1:  j 1b
