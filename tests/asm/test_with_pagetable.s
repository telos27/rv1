.option norvc
.section .text
.globl _start

_start:
    li x29, 1
    
    # Simple test: write/read 0x80003000
    li t0, 0x80003000
    li t1, 0x12345678
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    
    # Success
    li x29, 100
    li x28, 0xDEADBEEF
    ebreak

fail:
    li x28, 0xDEADDEAD
    ebreak

.section .data
.align 12
page_table_l1:
    .fill 1024, 4, 0x00000000
