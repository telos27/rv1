.option norvc
.section .text
.globl _start

_start:
    li x29, 1
    
    # Setup page table (like test_vm_non_identity_basic stage 2)
    la t0, page_table_l1
    li t1, 0x20000CCF          # PTE for VA 0x80000000 → PA 0x80003000
    li t2, 2048                # Offset to entry 512
    add t2, t0, t2
    sw t1, 0(t2)               # Write PTE
    
    # Now try to access 0x80003000
    li t0, 0x80003000
    li t1, 0xABCDEF01
    sw t1, 0(t0)
    lw t2, 0(t0)
    bne t1, t2, fail
    
    # Success
    li x28, 0xDEADBEEF
    ebreak

fail:
    li x28, 0xDEADDEAD
    ebreak

.section .data
.align 12
page_table_l1:
    .fill 1024, 4, 0x00000000
