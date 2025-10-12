# Test: Basic Supervisor Mode CSR Access and SRET
# Tests Phase 2 implementation of S-mode CSRs and privilege transitions

.section .text
.globl _start

_start:
    # We start in M-mode (privilege = 11)

    # Test 1: Access M-mode CSR from M-mode (should succeed)
    li      t0, 0x12345678
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, fail

    # Test 2: Configure trap delegation
    # Delegate all exceptions to S-mode (for testing)
    li      t0, 0xFFFFFFFF
    csrw    medeleg, t0

    # Test 3: Set up S-mode trap vector
    la      t0, s_trap_handler
    csrw    stvec, t0

    # Test 4: Read SSTATUS (should work from M-mode)
    csrr    t0, sstatus

    # Test 5: Write to S-mode CSR from M-mode (should succeed)
    li      t0, 0xABCD
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, fail

    # Test 6: Enter S-mode via MRET
    # Set MSTATUS.MPP = 01 (S-mode)
    li      t0, 0x00000800        # MPP = 01 (S-mode) at bits [12:11]
    csrs    mstatus, t0

    # Set MEPC to S-mode entry point
    la      t0, s_mode_entry
    csrw    mepc, t0

    # Execute MRET to enter S-mode
    mret

s_mode_entry:
    # Now in S-mode (privilege = 01)

    # Test 7: Access S-mode CSR from S-mode (should succeed)
    li      t0, 0x5555
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, fail

    # Test 8: Try to access M-mode CSR from S-mode (should cause illegal instruction)
    # This will trigger an illegal instruction exception
    # which should be delegated to S-mode trap handler
    csrr    t0, mscratch           # This should fail!

    # If we get here, privilege checking is broken
    j       fail

s_trap_handler:
    # S-mode trap handler
    # Check that we got illegal instruction exception (cause = 2)
    csrr    t0, scause
    li      t1, 2                  # Illegal instruction
    bne     t0, t1, fail

    # Test 9: Return to M-mode
    # We'll use ECALL to trap back to M-mode
    # First set up M-mode trap handler
    la      t0, m_trap_handler
    csrw    mtvec, t0

    # Execute ECALL (should go to M-mode since we're in S-mode)
    ecall

    # Should not reach here
    j       fail

m_trap_handler:
    # Back in M-mode
    # Check cause is ECALL from S-mode (cause = 9)
    csrr    t0, mcause
    li      t1, 9                  # ECALL from S-mode
    bne     t0, t1, fail

    # SUCCESS!
    j       pass

pass:
    # Write success pattern to test output
    li      a0, 0x1              # Exit code 1 = PASS
    li      a1, 0xDEADBEEF       # Magic value
    ebreak

fail:
    # Write failure pattern to test output
    li      a0, 0x0              # Exit code 0 = FAIL
    li      a1, 0xBADC0DE        # Error code
    ebreak

# Align to ensure proper instruction fetch
.align 4
