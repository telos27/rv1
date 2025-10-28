# Test: Simple CLINT Read Test
# Purpose: Verify bus correctly extracts 32-bit portions from 64-bit CLINT registers

.section .text
.globl _start

_start:
    # Write a known value to MTIMECMP
    li      a0, 0x02004000      # MTIMECMP base
    li      a1, 0x12345678      # Low word
    li      a2, 0xABCDEF00      # High word

    sw      a1, 0(a0)           # Write low word
    sw      a2, 4(a0)           # Write high word

    # Read back and verify
    lw      t0, 0(a0)           # Read low word
    lw      t1, 4(a0)           # Read high word

    # Compare
    bne     t0, a1, fail
    bne     t1, a2, fail

pass:
    li      a0, 0x10000000
    li      a1, 'P'
    sb      a1, 0(a0)
    j       end

fail:
    li      a0, 0x10000000
    li      a1, 'F'
    sb      a1, 0(a0)

end:
    li      a0, 1
    li      a1, 0
    ecall
