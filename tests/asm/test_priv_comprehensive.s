# ==============================================================================
# Test: Comprehensive Privilege Mode Regression (Phase 7.2)
# ==============================================================================
#
# Purpose: All-in-one regression test covering major privilege features
#
# Test Flow:
#   1. Basic privilege transitions (M/S/U)
#   2. CSR access from each mode
#   3. Trap delegation (medeleg)
#   4. State machine (MPIE/SPIE, MPP/SPP)
#   5. Exception handling from each mode
#   6. Verify all major features work together
#
# Expected Result: All tests pass, comprehensive regression confirmed
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE

    # Initialize test stage counter
    li      s11, 0          # Stage counter for debugging

    ###########################################################################
    # STAGE 1: Basic M → S → M Transition
    ###########################################################################
    li      s11, 1
    TEST_STAGE 1

    # Enter S-mode
    ENTER_SMODE_M stage1_smode

stage1_smode:
    # Verify S-mode by writing sscratch
    li      t0, 0xAAAAAAAA
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    # Return to M-mode via ECALL
    ecall

    # Execution continues in M-mode trap handler...

    ###########################################################################
    # STAGE 2: M → S → U → S → M Transition Chain
    ###########################################################################
stage2:
    li      s11, 2
    TEST_STAGE 2

    # Delegate ECALL from U-mode to S-mode
    DELEGATE_EXCEPTION CAUSE_ECALL_U

    # Enter S-mode
    ENTER_SMODE_M stage2_smode

stage2_smode:
    # From S-mode, enter U-mode
    ENTER_UMODE_S stage2_umode

stage2_umode:
    # In U-mode, trigger ECALL (should go to S-mode handler)
    ecall
    # Should never reach here
    j       test_fail

    ###########################################################################
    # STAGE 3: CSR Access Verification
    ###########################################################################
stage3:
    li      s11, 3
    TEST_STAGE 3

    # Clear delegation for this test
    CLEAR_EXCEPTION_DELEGATION

    # Test that S-mode CSR access works
    ENTER_SMODE_M stage3_smode

stage3_smode:
    # Write and read S-mode CSRs
    li      t0, 0x11111111
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

    # Write and read STVEC
    la      t0, s_trap_handler
    csrw    stvec, t0
    csrr    t1, stvec
    bne     t0, t1, test_fail

    # Attempt to access M-mode CSR (should trap)
    csrr    t0, mscratch    # Illegal in S-mode
    # Should never reach here
    j       test_fail

    ###########################################################################
    # STAGE 4: State Machine Verification (MPIE/MIE, MPP)
    ###########################################################################
stage4:
    li      s11, 4
    TEST_STAGE 4

    # Test 4a: MRET state transitions
    # Set MPIE=0, MIE=1
    DISABLE_MIE
    li      t0, MSTATUS_MPIE
    csrrc   zero, mstatus, t0   # Clear MPIE

    # Set MIE
    ENABLE_MIE

    # Set MPP=S, enter S-mode
    SET_MPP PRIV_S
    la      t0, stage4_after_mret
    csrw    mepc, t0
    mret

stage4_after_mret:
    # After MRET: MIE should be 0 (from MPIE), MPIE should be 1
    csrr    t0, mstatus
    li      t1, MSTATUS_MIE
    and     t2, t0, t1
    bnez    t2, test_fail       # MIE should be clear

    li      t1, MSTATUS_MPIE
    and     t2, t0, t1
    beqz    t2, test_fail       # MPIE should be set

    ###########################################################################
    # STAGE 5: Exception Handling from Each Mode
    ###########################################################################
stage5:
    li      s11, 5
    TEST_STAGE 5

    # Test 5a: ECALL from M-mode
    ecall

stage5_after_mecall:
    # Test 5b: ECALL from S-mode
    ENTER_SMODE_M stage5_smode

stage5_smode:
    ecall

stage5_after_secall:
    # Test 5c: ECALL from U-mode (with delegation)
    DELEGATE_EXCEPTION CAUSE_ECALL_U
    ENTER_SMODE_M stage5_smode2

stage5_smode2:
    ENTER_UMODE_S stage5_umode

stage5_umode:
    ecall

    ###########################################################################
    # STAGE 6: Delegation Edge Cases
    ###########################################################################
stage6:
    li      s11, 6
    TEST_STAGE 6

    # Clear all delegations first
    CLEAR_EXCEPTION_DELEGATION

    # Test delegation enable/disable
    DELEGATE_EXCEPTION CAUSE_ILLEGAL_INSTR

    # Enter S-mode and trigger illegal instruction
    ENTER_SMODE_M stage6_smode

stage6_smode:
    # Trigger illegal instruction (should go to S-mode handler due to delegation)
    .word   0xFFFFFFFF      # Illegal instruction

    ###########################################################################
    # If we reach here, all stages passed!
    ###########################################################################
test_success:
    TEST_PASS

# =============================================================================
# TRAP HANDLERS
# =============================================================================

m_trap_handler:
    csrr    t0, mcause

    # Check which stage we're in
    li      t1, 1
    beq     s11, t1, m_stage1_handler

    li      t1, 2
    beq     s11, t1, m_stage2_handler

    li      t1, 4
    beq     s11, t1, m_stage4_handler

    li      t1, 5
    beq     s11, t1, m_stage5_handler

    # Unexpected trap
    j       test_fail

m_stage1_handler:
    # Should be ECALL from S-mode
    li      t1, CAUSE_ECALL_S
    bne     t0, t1, test_fail
    # Continue to stage 2
    j       stage2

m_stage2_handler:
    # Should be ECALL from S-mode (after U→S→M chain)
    li      t1, CAUSE_ECALL_S
    bne     t0, t1, test_fail
    # Continue to stage 3
    j       stage3

m_stage4_handler:
    # Should be illegal instruction from S-mode (accessing mscratch)
    li      t1, CAUSE_ILLEGAL_INSTR
    bne     t0, t1, test_fail
    # Continue to stage 4
    j       stage4

m_stage5_handler:
    # Check cause
    li      t1, CAUSE_ECALL_M
    beq     t0, t1, m_stage5_mecall

    li      t1, CAUSE_ECALL_S
    beq     t0, t1, m_stage5_secall

    # Unexpected
    j       test_fail

m_stage5_mecall:
    # Continue after M-mode ECALL
    la      t0, stage5_after_mecall
    csrw    mepc, t0
    mret

m_stage5_secall:
    # Continue after S-mode ECALL
    la      t0, stage5_after_secall
    csrw    mepc, t0
    mret

s_trap_handler:
    csrr    t0, scause

    # Check which stage
    li      t1, 2
    beq     s11, t1, s_stage2_handler

    li      t1, 5
    beq     s11, t1, s_stage5_handler

    li      t1, 6
    beq     s11, t1, s_stage6_handler

    # Unexpected
    j       test_fail

s_stage2_handler:
    # Should be ECALL from U-mode
    li      t1, CAUSE_ECALL_U
    beq     t0, t1, s_stage2_ecall_u

    # Could also be illegal instruction
    li      t1, CAUSE_ILLEGAL_INSTR
    beq     t0, t1, s_stage2_ecall_u

    j       test_fail

s_stage2_ecall_u:
    # From S-mode handler, return to M-mode via ECALL
    ecall

s_stage5_handler:
    # Should be ECALL from U-mode
    li      t1, CAUSE_ECALL_U
    bne     t0, t1, test_fail

    # Return to M-mode
    ecall

s_stage6_handler:
    # Should be illegal instruction (delegated)
    li      t1, CAUSE_ILLEGAL_INSTR
    bne     t0, t1, test_fail

    # Clear delegation and continue to success
    CLEAR_EXCEPTION_DELEGATION
    j       test_success

# =============================================================================
# FAILURE HANDLER
# =============================================================================
test_fail:
    TEST_FAIL

# =============================================================================
# DATA SECTION
# =============================================================================
TRAP_TEST_DATA_AREA
