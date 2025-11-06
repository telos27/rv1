.option norvc
.section .text
.globl _start

_start:
    # Read SATP
    csrr t0, satp
    
    # Check if zero
    bnez t0, fail
    
    # Pass
    li t0, 0xDEADBEEF
    mv x28, t0
    ebreak

fail:
    # SATP was not zero - store its value in x28
    mv x28, t0
    ebreak
