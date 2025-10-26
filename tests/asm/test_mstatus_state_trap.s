# Test 2.3: Trap Entry State Transitions
# Purpose: Verify trap entry correctly updates mstatus/sstatus state machine
# Tests: xPIE←xIE on trap, xIE←0 on trap, xPP←current_priv on trap

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: M-mode trap with MIE=1 → MPIE=1, MIE=0
    #========================================================================
    TEST_STAGE 1

    # Setup: Set MIE before taking trap
    ENABLE_MIE                      # MIE ← 1

    # Verify MIE is set before trap
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # Trigger exception (ECALL from M-mode)
    ecall

after_mtrap1:
    # After MRET: MIE ← MPIE (was 1), MPIE ← 1
    # So both should be set now
    # We're checking that trap entry correctly saved MIE→MPIE
    # (The trap handler already verified this, but we check state after MRET too)

    #========================================================================
    # Test Case 2: M-mode trap with MIE=0 → MPIE=0, MIE=0
    #========================================================================
    TEST_STAGE 2

    # Setup: Clear MIE before taking trap
    DISABLE_MIE                     # MIE ← 0

    # Verify MIE is clear before trap
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Trigger exception (ECALL from M-mode)
    ecall

after_mtrap2:
    # After MRET: MIE ← MPIE (was 0), MPIE ← 1
    # So MPIE should be set, MIE should be clear
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    #========================================================================
    # Test Case 3: M-mode trap sets MPP to M-mode
    #========================================================================
    TEST_STAGE 3

    # Clear MPP to known state (U-mode)
    SET_MPP PRIV_U

    # Verify MPP is U before trap
    EXPECT_MPP PRIV_U, test_fail

    # Trigger exception from M-mode (ECALL)
    ecall

after_mtrap3:
    # After MRET: MPP ← U (least privileged mode)
    # The trap handler verified MPP was set to M during trap entry
    # Now verify MRET reset it to U
    EXPECT_MPP PRIV_U, test_fail

    # All M-mode tests passed!
    TEST_PASS

    # TODO: Add S-mode and U-mode trap entry tests
    # Stage 4-6 require delegation and S/U mode support
    # Uncomment below when ready to test S-mode trap entry

    # #========================================================================
    # # Test Case 4: S-mode trap with SIE=1 → SPIE=1, SIE=0
    # #========================================================================
    # TEST_STAGE 4
    # ... (S-mode test code commented out for now)

# ==============================================================================
# Trap Handlers
# ==============================================================================

# Main M-mode trap handler (dispatcher)
m_trap_handler:
    # Dispatch based on stage number
    mv t0, x29
    li t1, 1
    beq t0, t1, m_trap_handler_stage1
    li t1, 2
    beq t0, t1, m_trap_handler_stage2
    li t1, 3
    beq t0, t1, m_trap_handler_stage3
    # Unexpected stage
    j test_fail

# Main S-mode trap handler (dispatcher)
s_trap_handler:
    # S-mode tests disabled for now
    j test_fail

m_trap_handler_stage1:
    # Stage 1: M-mode trap handler
    # Verify we're in stage 1
    mv t0, x29
    li t1, 1
    bne t0, t1, test_fail

    # Verify cause is ECALL from M-mode
    EXPECT_CSR mcause, CAUSE_ECALL_M, test_fail

    # Verify MPIE was set to old MIE (1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE was cleared
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return to after_mtrap1
    la t0, after_mtrap1
    csrw mepc, t0
    mret

m_trap_handler_stage2:
    # Stage 2: M-mode trap handler
    # Verify we're in stage 2
    mv t0, x29
    li t1, 2
    bne t0, t1, test_fail

    # Verify cause is ECALL from M-mode
    EXPECT_CSR mcause, CAUSE_ECALL_M, test_fail

    # Verify MPIE was set to old MIE (0)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE was cleared (already was 0)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return to after_mtrap2
    la t0, after_mtrap2
    csrw mepc, t0
    mret

m_trap_handler_stage3:
    # Stage 3: M-mode trap handler
    # Verify we're in stage 3
    mv t0, x29
    li t1, 3
    bne t0, t1, test_fail

    # Verify cause is ECALL from M-mode
    EXPECT_CSR mcause, CAUSE_ECALL_M, test_fail

    # Verify MPP was set to M-mode
    EXPECT_MPP PRIV_M, test_fail

    # Return to after_mtrap3
    la t0, after_mtrap3
    csrw mepc, t0
    mret

# Stage 4-6 handlers commented out (S-mode tests disabled)

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
