# Test: Basic Register Operations
# Purpose: Verify basic register operations work

.section .text
.globl _start

_start:
    # Load immediate values
    li a0, 0x11111111
    li a1, 0x22222222
    li a2, 0x33333333

    # Simple arithmetic
    add t0, a0, a1
    
    # Exit
    ebreak

.section .data
