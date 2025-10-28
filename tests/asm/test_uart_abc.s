# test_uart_abc.s - Minimal UART test to isolate character duplication bug
# Writes "ABC\n" to UART and exits
# Expected output: ABC (3 characters + newline)
# If bug present: AABBCC or similar duplication pattern

.section .text
.globl _start

_start:
    # Initialize UART base address
    li      a0, 0x10000000          # UART base address (THR at offset 0)

    # Write 'A' (0x41)
    li      a1, 0x41
    sb      a1, 0(a0)

    # Small delay (10 NOPs) to space out writes
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    # Write 'B' (0x42)
    li      a1, 0x42
    sb      a1, 0(a0)

    # Small delay
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    # Write 'C' (0x43)
    li      a1, 0x43
    sb      a1, 0(a0)

    # Small delay
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop

    # Write newline (0x0A)
    li      a1, 0x0A
    sb      a1, 0(a0)

    # Exit via EBREAK
    ebreak

.section .data
# No data needed for this test
