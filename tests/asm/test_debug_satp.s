.option norvc
.section .text
.globl _start

_start:
    # Verify SATP is 0
    csrr t0, satp
    # Store SATP for inspection
    li t1, 0x80002FF0
    sw t0, 0(t1)
    
    # Try to access 0x80003000
    li t0, 0x80003000
    li t1, 0xAABBCCDD
    sw t1, 0(t0)
    lw t2, 0(t0)
    
    # Success
    li x28, 0xDEADBEEF
    ebreak
