# Test: Phase 10.2 - CSR Privilege Violation
# Tests that S-mode cannot access M-mode CSRs and triggers illegal instruction exception
#
# Test flow:
# 1. M-mode: Set up exception handler
# 2. M-mode → S-mode
# 3. S-mode: Try to read M-mode CSR (should trigger illegal instruction)
# 4. M-mode handler: Verify exception cause = 2 (illegal instruction)
# 5. M-mode: Test more privilege violations

.section .text
.globl _start

_start:
    li      t6, 0             # Test counter
    li      s10, 0            # Exception counter

# ============================================================================
# Stage 1: Setup trap handler
# ============================================================================
stage1_setup:
    addi    t6, t6, 1         # Stage 1

    # Set M-mode trap handler
    la      t0, m_trap_handler
    csrw    mtvec, t0

    # Clear medeleg - no delegation (all traps go to M-mode)
    csrw    medeleg, zero

# ============================================================================
# Stage 2: Enter S-mode
# ============================================================================
stage2_enter_smode:
    addi    t6, t6, 1         # Stage 2

    # Set MSTATUS.MPP = 01 (S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF    # Clear MPP
    and     t0, t0, t1
    li      t1, 0x00000800    # MPP = 01 (S-mode)
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set MEPC to S-mode code
    la      t0, s_mode_tests
    csrw    mepc, t0

    # Transition to S-mode
    mret

# ============================================================================
# S-mode Tests - Attempt to access M-mode CSRs
# ============================================================================
s_mode_tests:
    addi    t6, t6, 1         # Stage 3

# ----------------------------------------------------------------------------
# Test 1: Read M-mode CSR from S-mode (should fail)
# ----------------------------------------------------------------------------
test1_read_mmode_csr:
    # Save return address for after exception
    la      s0, after_test1

    # Try to read MSCRATCH (M-mode only CSR)
    # This should trigger illegal instruction exception
    csrr    t0, mscratch      # ← Should trap here!

    # Should NOT reach here
    j       test_fail

after_test1:
    addi    t6, t6, 1         # Stage 4
    # Verify we got here via exception
    li      t0, 1
    bne     s10, t0, test_fail  # Should have had 1 exception

# ----------------------------------------------------------------------------
# Test 2: Write M-mode CSR from S-mode (should fail)
# ----------------------------------------------------------------------------
test2_write_mmode_csr:
    la      s0, after_test2

    # Try to write MTVEC (M-mode only CSR)
    li      t0, 0x80001000
    csrw    mtvec, t0         # ← Should trap here!

    j       test_fail

after_test2:
    addi    t6, t6, 1         # Stage 5
    li      t0, 2
    bne     s10, t0, test_fail  # Should have had 2 exceptions

# ----------------------------------------------------------------------------
# Test 3: Modify M-mode CSR with CSRRS (should fail)
# ----------------------------------------------------------------------------
test3_csrrs_mmode:
    la      s0, after_test3

    # Try CSRRS on MSTATUS (M-mode CSR)
    li      t0, 0x8
    csrrs   t1, mstatus, t0   # ← Should trap here!

    j       test_fail

after_test3:
    addi    t6, t6, 1         # Stage 6
    li      t0, 3
    bne     s10, t0, test_fail  # Should have had 3 exceptions

# ----------------------------------------------------------------------------
# Test 4: Verify S-mode CAN access S-mode CSRs
# ----------------------------------------------------------------------------
test4_smode_csr_ok:
    addi    t6, t6, 1         # Stage 7

    # This should NOT trigger an exception
    li      t0, 0xAAAAAAAA
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    # Exception count should still be 3 (no new exception)
    li      t0, 3
    bne     s10, t0, test_fail

# ----------------------------------------------------------------------------
# Test 5: Return to M-mode and verify
# ----------------------------------------------------------------------------
test5_return_to_mmode:
    addi    t6, t6, 1         # Stage 8

    # ECALL to return to M-mode
    ecall

    # Should not reach here
    j       test_fail

# ============================================================================
# M-mode Trap Handler
# ============================================================================
m_trap_handler:
    # Check exception cause
    csrr    t0, mcause

    # Check if it's ECALL from S-mode (cause 9)
    li      t1, 9
    beq     t0, t1, handle_ecall

    # Check if it's illegal instruction (cause 2)
    li      t1, 2
    beq     t0, t1, handle_illegal_inst

    # Unexpected exception
    j       test_fail

handle_illegal_inst:
    # Increment exception counter
    addi    s10, s10, 1

    # Get MEPC (faulting instruction)
    csrr    t0, mepc

    # Skip the faulting instruction (4 bytes)
    addi    t0, t0, 4
    csrw    mepc, t0

    # Jump to return address saved in s0
    # Set MEPC to s0 instead
    csrw    mepc, s0

    # Return to S-mode (restore MPP = S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF    # Clear MPP
    and     t0, t0, t1
    li      t1, 0x00000800    # MPP = 01 (S-mode)
    or      t0, t0, t1
    csrw    mstatus, t0

    mret

handle_ecall:
    # ECALL from S-mode - test is complete
    # Verify exception count
    li      t0, 3
    bne     s10, t0, test_fail

    # SUCCESS!
    j       test_pass

# ============================================================================
# SUCCESS
# ============================================================================
test_pass:
    li      a0, 1             # Success
    mv      a1, t6            # Stages completed
    mv      a2, s10           # Exception count (should be 3)
    li      t5, 0xDEADBEEF
    ebreak

# ============================================================================
# FAILURE
# ============================================================================
test_fail:
    li      a0, 0             # Failure
    mv      a1, t6            # Failed stage
    mv      a2, s10           # Exception count
    ebreak

.align 4
