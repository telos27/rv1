# Test: Comprehensive Supervisor Mode Test
# Tests:
# 1. M-mode → S-mode transition via MRET
# 2. S-mode CSR access
# 3. Illegal instruction exception when S-mode accesses M-CSR
# 4. Trap delegation
# 5. S-mode → M-mode transition via trap

.section .text
.globl _start

_start:
    ###########################################################################
    # TEST 1: Initial M-mode verification
    ###########################################################################
    li      t0, 0xAAAA5555
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, test_fail

    ###########################################################################
    # TEST 2: Setup trap delegation
    ###########################################################################
    # Delegate illegal instruction exceptions to S-mode
    li      t0, 0x00000004        # Bit 2 = illegal instruction
    csrw    medeleg, t0

    # Set S-mode trap vector
    la      t0, s_trap_handler
    csrw    stvec, t0

    # Set M-mode trap vector (for non-delegated traps)
    la      t0, m_trap_handler
    csrw    mtvec, t0

    ###########################################################################
    # TEST 3: Enter S-mode via MRET
    ###########################################################################
    # Set MSTATUS.MPP = 01 (S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF        # Mask to clear MPP[12:11]
    and     t0, t0, t1
    li      t1, 0x00000800        # MPP = 01 (S-mode)
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set MEPC to S-mode code
    la      t0, s_mode_entry
    csrw    mepc, t0

    # Enter S-mode
    mret

s_mode_entry:
    ###########################################################################
    # Now in S-mode
    # TEST 4: Access S-mode CSRs
    ###########################################################################
    li      t0, 0x12345678
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    ###########################################################################
    # TEST 5: Try to access M-mode CSR (should cause illegal instruction)
    ###########################################################################
    # This should trap to S-mode handler (because medeleg[2] is set)
    csrr    t0, mscratch          # ILLEGAL in S-mode!

    # Should never reach here
    j       test_fail

s_trap_handler:
    ###########################################################################
    # S-mode trap handler
    # TEST 6: Verify we got illegal instruction exception
    ###########################################################################
    csrr    t0, scause
    li      t1, 2                 # Illegal instruction
    bne     t0, t1, test_fail

    # Check SEPC points to the faulting instruction
    csrr    t2, sepc

    ###########################################################################
    # TEST 7: Use ECALL to return to M-mode
    ###########################################################################
    # Clear delegation of ECALL from S-mode
    # so it goes to M-mode
    ecall                         # Should go to M-mode

    # Should not reach here
    j       test_fail

m_trap_handler:
    ###########################################################################
    # M-mode trap handler
    # TEST 8: Verify we got ECALL from S-mode
    ###########################################################################
    csrr    t0, mcause
    li      t1, 9                 # ECALL from S-mode
    bne     t0, t1, test_fail

    # SUCCESS!
    j       test_pass

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
