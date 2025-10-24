# Test: Debug mstatus read - check what's failing

.section .text
.globl _start

_start:
    # Initialize trap handler
    la t0, m_trap_handler
    csrw mtvec, t0
    
    # Mark stage 1
    li t4, 1

    # Test: Read mstatus
    csrr a0, mstatus
    
    # Mark stage 2 - if we get here, read worked
    li t4, 2
    
    # Write to mstatus
    li t0, 0x00001888
    csrw mstatus, t0
    
    # Mark stage 3
    li t4, 3
    
    # Read back
    csrr a1, mstatus
    
    # Mark stage 4 - success!
    li t4, 4
    li t3, 0xDEADBEEF
    ebreak

m_trap_handler:
    # Save cause
    csrr t0, mcause
    # Save EPC
    csrr t1, mepc
    # Mark failure
    li t3, 0xDEADDEAD
    ebreak

.align 4
