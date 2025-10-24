# Test: Basic mstatus read/write
# Purpose: Minimal test to verify mstatus CSR operations

.section .text
.globl _start

_start:
    # Initialize - set up trap handler
    la t0, m_trap_handler
    csrw mtvec, t0

    # Test 1: Read mstatus initial value
    csrr a0, mstatus
    # a0 should have some value (at least MPP bits should be set)
    
    # Test 2: Write a known value to mstatus
    li t0, 0x00001888          # MPP=11 (bits 12:11), MPIE=1 (bit 7), MIE=1 (bit 3)
    csrw mstatus, t0
    
    # Test 3: Read it back
    csrr a1, mstatus
    # a1 should = 0x1888 (or at least have those bits set)
    
    # Test 4: Compare write and read
    mv a2, t0                   # a2 = what we wrote
    # a2 should match a1
    
    # Store results for inspection
    mv t3, a1                   # Copy to t3 for easy viewing
    
    # Exit
    ebreak

m_trap_handler:
    # Unexpected trap
    li t3, 0xBADBAD00
    ebreak

.align 4
