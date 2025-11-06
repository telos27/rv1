.option norvc
.section .text
.globl _start

.equ PA_DATA, 0x80003000

_start:
    li      x29, 1
    
    # Verify SATP is initially 0
    csrr    t0, satp
    bnez    t0, test_fail
    
    # Write test pattern
    li      t0, PA_DATA
    li      t1, 0xCAFEBABE
    sw      t1, 0(t0)
    li      t1, 0xDEADC0DE
    sw      t1, 4(t0)
    
    # Verify the writes succeeded
    li      t0, PA_DATA
    lw      t2, 0(t0)
    li      t3, 0xCAFEBABE
    bne     t2, t3, test_fail
    
    # Success!
    li      x29, 100
    li      x28, 0xDEADBEEF
    ebreak

test_fail:
    li      x28, 0xDEADDEAD
    ebreak
