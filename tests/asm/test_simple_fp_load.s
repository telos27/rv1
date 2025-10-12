# Simple FP Load Test - Matches simple_add pattern
.section .text
.globl _start

_start:
    li a0, 5
    li a1, 10
    add a2, a0, a1
    # Now try a simple FP operation
    fmv.w.x f0, a0      # Move integer to FP register
    fmv.x.w a3, f0      # Move back
    ebreak
