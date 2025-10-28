# Test: CLINT MTIMECMP Write Test
# Purpose: Minimal reproduction of FreeRTOS MTIMECMP write pattern
# Expected: Two SW instructions to 0x02004000/0x02004004 should reach CLINT

.section .text
.globl _start

_start:
    # Initialize test
    li      a0, 0x02004000      # MTIMECMP base address

    # Read current MTIME (to calculate future value)
    li      a1, 0x0200BFF8      # MTIME address
    lw      a2, 0(a1)           # Read mtime_low
    lw      a3, 4(a1)           # Read mtime_high

    # Add tick increment (50000 = 0xC350)
    li      a4, 0xC350          # 50000 cycles
    add     a2, a2, a4          # Add to low word
    sltu    a5, a2, a4          # Check carry
    add     a3, a3, a5          # Add carry to high word

    # Write MTIMECMP (mimics FreeRTOS pattern)
    # This should generate bus writes to CLINT!
    sw      a2, 0(a0)           # Write mtimecmp[31:0]  (addr 0x02004000)
    sw      a3, 4(a0)           # Write mtimecmp[63:32] (addr 0x02004004)

    # Verify write by reading back
    lw      t0, 0(a0)           # Read mtimecmp_low
    lw      t1, 4(a0)           # Read mtimecmp_high

    # Check if values match
    bne     t0, a2, test_fail
    bne     t1, a3, test_fail

test_pass:
    # SUCCESS: MTIMECMP written correctly
    li      a0, 0x10000000      # UART base
    li      a1, 'P'
    sb      a1, 0(a0)
    li      a1, 'A'
    sb      a1, 0(a0)
    li      a1, 'S'
    sb      a1, 0(a0)
    li      a1, 'S'
    sb      a1, 0(a0)
    li      a1, '\n'
    sb      a1, 0(a0)
    j       end_test

test_fail:
    # FAILURE: MTIMECMP readback mismatch
    li      a0, 0x10000000      # UART base
    li      a1, 'F'
    sb      a1, 0(a0)
    li      a1, 'A'
    sb      a1, 0(a0)
    li      a1, 'I'
    sb      a1, 0(a0)
    li      a1, 'L'
    sb      a1, 0(a0)
    li      a1, '\n'
    sb      a1, 0(a0)

end_test:
    # Signal completion
    li      a0, 1
    li      a1, 0
    ecall                       # Exit simulation
