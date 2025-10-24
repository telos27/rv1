# Test: Compare CSR reads - mscratch vs mstatus

.section .text
.globl _start

_start:
    # Initialize trap handler
    la t0, m_trap_handler
    csrw mtvec, t0

    # Test 1: Read mscratch (known to work in some tests)
    csrr a0, mscratch
    
    # Test 2: Read mstatus
    csrr a1, mstatus
    
    # If we get here, both worked
    li t3, 0xC0DEC0DE
    ebreak

m_trap_handler:
    # Trap occurred - mark which CSR caused it
    csrr t0, mepc               # Get faulting PC
    
    # Mark that we trapped
    li t3, 0xBAD00000           # BAD + trap PC in lower bits
    ebreak

.align 4
