# RV64I LWU Test
# Test LWU (Load Word Unsigned) - RV64-specific

.section .text
.globl _start

.option norvc

_start:
    li      a0, 0x2000              # Address
    li      a1, 0xFEDCBA98          # Negative word value (bit 31 = 1)
    sw      a1, 0(a0)               # Store word

    # Test LWU - should zero-extend to 64 bits
    lwu     a2, 0(a0)               # Load word unsigned

    # Expected: a2 = 0x00000000FEDCBA98 (zero-extended)
    # Compare with sign-extended version
    lw      a3, 0(a0)               # Load word (sign-extended)

    # Expected: a3 = 0xFFFFFFFFFEDCBA98 (sign-extended)

    # Check if upper 32 bits of a2 are zero
    srli    a4, a2, 32              # Shift right 32 bits
    # a4 should be 0

    # Set result: if a4==0 and a2[31:0]==a1[31:0], success
    li      a0, 1                   # Assume success
    bnez    a4, fail                # If upper bits not zero, fail

    # Verify lower 32 bits match
    li      t0, 0xFEDCBA98
    bne     a2, t0, fail

success:
    li      a0, 1
    j       done

fail:
    li      a0, 0

done:
    nop
    nop
    ebreak
