# Test: Simple MRET test
# Purpose: Verify MRET updates mstatus correctly

.section .text
.globl _start

_start:
    # Setup trap handler
    la t0, m_trap_handler
    csrw mtvec, t0

    # Read initial mstatus
    csrr s0, mstatus            # s0 = initial mstatus (should be ~0x1800)
    
    # Setup for MRET: Clear MPIE, Set MIE
    li t0, 0x00000080           # MPIE bit
    csrrc zero, mstatus, t0     # Clear MPIE
    li t0, 0x00000008           # MIE bit  
    csrrs zero, mstatus, t0     # Set MIE
    
    # Read mstatus before MRET
    csrr s1, mstatus            # s1 = mstatus before MRET
    
    # Set return address
    la t0, after_mret
    csrw mepc, t0
    
    # Execute MRET
    mret

after_mret:
    # Read mstatus after MRET
    csrr s2, mstatus            # s2 = mstatus after MRET
    
    # Expected: MIE should now be 0 (copied from MPIE which was 0)
    # Expected: MPIE should now be 1 (set by MRET)
    
    # Store for viewing
    mv a0, s0                   # Initial
    mv a1, s1                   # Before MRET
    mv a2, s2                   # After MRET
    
    # Success
    li t3, 0xDEADBEEF
    ebreak

m_trap_handler:
    li t3, 0xDEADDEAD
    ebreak

.align 4
