# Minimal LR/SC test to debug forwarding hazard
.section .text
.globl _start

_start:
    # Initialize test address and value
    li      a0, 0x80002000    # Test address
    li      a2, 1             # Increment value
    li      t0, 0             # Initial value
    sw      t0, 0(a0)         # Store 0 to memory

    # Test LR/SC with dependent ADD
    lr.w    a4, (a0)          # Load 0 from memory
    nop                        # Give time for atomic to complete
    nop
    add     a4, a4, a2        # Should compute 0 + 1 = 1
    sc.w    t1, a4, (a0)      # Store 1 to memory

    # Check result
    lw      t2, 0(a0)         # Load from memory
    li      t3, 1             # Expected value
    bne     t2, t3, fail

    # Success
    li      a0, 0
    j       done

fail:
    li      a0, 1

done:
    # Write result to signature area
    li      t0, 0x80003000
    sw      a0, 0(t0)

    # End simulation
    ebreak
