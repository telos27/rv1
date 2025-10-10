# Test load-use hazard detection
# This should stall when a load result is immediately used

.section .text
.globl _start

_start:
    # Set up test data in memory
    li x1, 0x1000        # Base address
    li x2, 0xABCD1234    # Test data
    sw x2, 0(x1)         # Store test data

    # Test 1: Load-use hazard (should stall)
    lw x3, 0(x1)         # Load from memory
    addi x4, x3, 1       # Use immediately (load-use hazard!)

    # Test 2: Load with 1 NOP (no hazard)
    lw x5, 0(x1)         # Load from memory
    nop                  # NOP
    addi x6, x5, 2       # Use after 1 cycle

    # Verify results
    li x7, 0xABCD1235    # Expected x4
    bne x4, x7, fail

    li x7, 0xABCD1236    # Expected x6
    bne x6, x7, fail

    li x10, 42           # Success
    j end

fail:
    li x10, 0xBAD

end:
    ecall
