.option norvc
.section .text
.globl _start

_start:
    # Read what was written to 0x80002FE0 (SATP during test)
    li t0, 0x80002FE0
    lw t1, 0(t0)
    
    # Read what was written to 0x80002FF0 (value read from 0x80003000)
    li t0, 0x80002FF0
    lw t2, 0(t0)
    
    # Read what was written to 0x80002FF4 (address that was loaded from)
    lw t3, 4(t0)
    
    # Success
    li x28, 0xDEADBEEF
    ebreak
