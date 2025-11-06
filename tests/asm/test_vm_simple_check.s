.option norvc
.section .text
.globl _start

.equ SATP_MODE_SV32, 0x80000000

_start:
    li x29, 1
    
    # Write test data to PA 0x80003000
    li t0, 0x80003000
    li t1, 0xABCD1234
    sw t1, 0(t0)
    
    # Read it back
    lw t2, 0(t0)
    bne t1, t2, fail
    
    # Success
    li x29, 100
    li t0, 0xDEADBEEF
    mv x28, t0
    ebreak

fail:
    li t0, 0xDEADDEAD
    mv x28, t0
    ebreak
