# Test JAL instruction sequences
# This test verifies that JAL instructions correctly write return addresses
# even when followed immediately by other instructions

.section .text
.globl _start

_start:
    # Test 1: Single JAL
    li t0, 0xAAAA0000       # Initialize t0
    jal ra, func1          # Should write ra = PC+4
    # ra should be address of next instruction
    li t1, 0xBBBB0000
    bne ra, zero, test2     # Verify ra was written (non-zero)
    j fail

test2:
    # Test 2: Back-to-back JALs
    jal s0, func1          # Should write s0 = PC+4
    jal s1, func2          # Should write s1 = PC+4
    # Both s0 and s1 should have been written
    beq s0, zero, fail
    beq s1, zero, fail

    # Test 3: JAL followed by branch
    jal t2, func1          # Should write t2 = PC+4
    beq t0, t1, skip       # Branch (likely not taken)
skip:
    beq t2, zero, fail      # Verify t2 was written

    j pass

func1:
    li a0, 0x1111
    ret

func2:
    li a0, 0x2222
    ret

pass:
    li a0, 0               # Success
    li a7, 93              # Exit syscall
    ecall

fail:
    li a0, 1               # Failure
    li a7, 93
    ecall
