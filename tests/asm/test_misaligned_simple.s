# Simple misaligned access test
# Tests if misaligned exception is triggered and handled

.section .text
.globl _start

_start:
    # Set up trap handler
    la   x1, trap_handler
    csrrw x0, mtvec, x1      # Set mtvec to trap_handler address

    # Test 1: Try misaligned load (should trap)
    li   x2, 0x1001          # Odd address (misaligned for halfword)
    lh   x3, 0(x2)           # Should trigger misaligned load exception

    # If we get here, trap handler worked
    li   x10, 1              # Success indicator
    j    _end

trap_handler:
    # Simple trap handler
    csrr x4, mcause          # Read exception cause
    csrr x5, mepc            # Read exception PC
    csrr x6, mtval           # Read exception value (faulting address)

    # Skip faulting instruction (mepc += 4)
    addi x5, x5, 4
    csrw mepc, x5

    # Return from trap
    mret

_end:
    # Infinite loop
    j _end
