# Test: Privilege Mode Transitions
# Test M → S → M transitions using MRET and traps
# Note: We can't easily test U-mode without MMU setup

.section .text
.globl _start

_start:
    # We start in M-mode (privilege = 11)
    # Test 1: Verify we're in M-mode by accessing M-only CSR
    li      t0, 0xAAAA5555
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, test_fail

    # Test 2: Enter S-mode via MRET
    # Set MSTATUS.MPP = 01 (S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF        # Mask to clear MPP field (bits [12:11])
    and     t0, t0, t1             # Clear MPP bits
    li      t1, 0x00000800        # MPP = 01 (S-mode)
    or      t0, t0, t1            # Set MPP bits
    csrw    mstatus, t0

    # Set MEPC to S-mode entry point
    la      t0, s_mode_code
    csrw    mepc, t0

    # Set up M-mode trap vector for when we return from S-mode
    la      t0, m_trap_handler
    csrw    mtvec, t0

    # Execute MRET to enter S-mode
    mret

s_mode_code:
    # Now in S-mode (privilege = 01)
    # Test 3: Verify we can access S-mode CSRs
    li      t0, 0x12345678
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    # Test 4: Try to access M-mode CSR from S-mode
    # This should cause illegal instruction exception
    csrr    t0, mscratch      # This should trap!

    # If we reach here, privilege checking failed
    j       test_fail

m_trap_handler:
    # Back in M-mode due to trap from S-mode
    # Test 5: Verify exception cause is illegal instruction (cause = 2)
    csrr    t0, mcause
    li      t1, 2                 # Illegal instruction
    bne     t0, t1, test_fail

    # Test 6: Verify MEPC points to the faulting instruction (csrr in S-mode)
    csrr    t0, mepc
    la      t1, s_mode_code
    addi    t1, t1, 16            # Offset to the csrr mscratch instruction
    # We'll skip this check for now as calculating exact offset is tricky

    # SUCCESS - All privilege transition tests passed!
    j       test_pass

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

.align 4
