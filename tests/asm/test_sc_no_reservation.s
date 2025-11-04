# Test: SC without LR should fail and return 1
# Also verify memory is NOT written

.section .text
.globl _start

_start:
    # Initialize test data
    la x10, testdata
    li x11, 0xdeadbeef

    # Try SC without prior LR (should FAIL)
    sc.w x12, x11, (x10)

    # Check return value (should be 1 = failure)
    li x13, 1
    bne x12, x13, fail

    # Check memory was NOT written (should still be 0)
    lw x14, 0(x10)
    li x15, 0
    bne x14, x15, fail

    # SUCCESS
    li x10, 1
    j end

fail:
    li x10, 0

end:
    # Exit via ECALL
    li x17, 93        # exit syscall
    ecall
    j end

.section .data
.align 3
testdata:
    .word 0
