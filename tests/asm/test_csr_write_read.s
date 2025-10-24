# Test: CSR Write-Then-Read
# Purpose: Check if writing a CSR breaks subsequent reads

.section .text
.globl _start

_start:
    # Setup
    la t0, m_trap_handler
    csrw mtvec, t0

    # Test 1: Read mstatus (should work)
    csrr a0, mstatus
    
    # Test 2: Write to mscratch (a different CSR)
    li t0, 0x12345678
    csrw mscratch, t0
    
    # Test 3: Read mstatus again (does write to mscratch break mstatus reads?)
    csrr a1, mstatus
    
    # Test 4: Write to mstatus itself
    li t0, 0x00001888
    csrw mstatus, t0
    
    # Test 5: Read mstatus after writing to it
    csrr a2, mstatus
    
    # Store results
    mv s0, a0               # First read
    mv s1, a1               # After mscratch write
    mv s2, a2               # After mstatus write
    
    # Success
    li t3, 0xDEADBEEF
    ebreak

m_trap_handler:
    li t3, 0xDEADDEAD
    ebreak

.align 4
