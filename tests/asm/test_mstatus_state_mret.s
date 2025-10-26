# Test 2.1: MRET State Transitions
# Purpose: Verify MRET correctly updates mstatus state machine
# Tests: MIE←MPIE, MPIE←1, privilege←MPP, MPP←M

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: MRET with MPIE=0, MIE=1 → After MRET: MIE=0, MPIE=1
    #========================================================================
    TEST_STAGE 1

    # Setup: Clear MPIE, Set MIE
    DISABLE_MPIE                    # MPIE ← 0
    ENABLE_MIE                      # MIE ← 1
    SET_MPP PRIV_M                  # MPP ← M (stay in M-mode after MRET)

    # Set return address
    la t0, after_mret1
    csrw mepc, t0

    # Execute MRET
    mret

after_mret1:
    # Verify MIE is now 0 (copied from MPIE which was 0)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Verify MPIE is now 1 (set to 1 by MRET)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    #========================================================================
    # Test Case 2: MRET with MPIE=1, MIE=0 → After MRET: MIE=1, MPIE=1
    #========================================================================
    TEST_STAGE 2

    # Setup: Set MPIE, Clear MIE
    ENABLE_MPIE                     # MPIE ← 1
    DISABLE_MIE                     # MIE ← 0
    SET_MPP PRIV_M                  # MPP ← M (stay in M-mode after MRET)

    # Set return address
    la t0, after_mret2
    csrw mepc, t0

    # Execute MRET
    mret

after_mret2:
    # Verify MIE is now 1 (copied from MPIE which was 1)
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # Verify MPIE is now 1 (set to 1 by MRET)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    #========================================================================
    # Test Case 3: MRET with MPP=M → privilege stays M
    #========================================================================
    TEST_STAGE 3

    # Setup: MPP = M-mode (11)
    SET_MPP PRIV_M

    # Set return address
    la t0, after_mret3
    csrw mepc, t0

    # Execute MRET
    mret

after_mret3:
    # Verify we're still in M-mode by accessing M-mode CSR
    csrr t0, mstatus                # Should succeed in M-mode

    # Verify MPP is now U (set to least privileged mode per RISC-V spec)
    # Per spec: "xPP is set to the least-privileged supported mode (U if U-mode is implemented)"
    EXPECT_MPP PRIV_U, test_fail

    #========================================================================
    # Test Case 4: MRET with MPP=S → privilege becomes S
    #========================================================================
    TEST_STAGE 4

    # Setup: MPP = S-mode (01)
    SET_MPP PRIV_S

    # Set return address
    la t0, smode_code
    csrw mepc, t0

    # Execute MRET
    mret

smode_code:
    # Verify we're in S-mode by:
    # 1. Being able to access sstatus (S-mode CSR)
    # 2. NOT being able to access some M-mode only functionality

    # Access S-mode CSR (should work)
    li t0, 0x12345678
    csrw sscratch, t0
    csrr t1, sscratch
    bne t0, t1, test_fail

    # Return to M-mode for next test
    # Note: Can't use MRET from S-mode (would trap), so use ECALL
    # The M-mode trap handler will check for this and continue
    ecall

after_smode:
    #========================================================================
    # Test Case 5: MRET with MPP=U → privilege becomes U
    #========================================================================
    TEST_STAGE 5

    # Setup: MPP = U-mode (00)
    SET_MPP PRIV_U

    # Set return address
    la t0, umode_code
    csrw mepc, t0

    # Execute MRET
    mret

umode_code:
    # Verify we're in U-mode by attempting M-mode CSR access
    # This should trap with illegal instruction

    # Try to access M-mode CSR (should cause trap)
    csrr t0, mstatus
    
    # Should never reach here
    TEST_FAIL

m_trap_handler:
    # Check trap cause
    csrr t0, mcause

    # Check if it's an ECALL from S-mode (cause = 9)
    li t1, 9                        # CAUSE_ECALL_FROM_SMODE
    beq t0, t1, handle_smode_ecall

    # Otherwise, verify cause is illegal instruction (U-mode can't access mstatus)
    EXPECT_CSR mcause, CAUSE_ILLEGAL_INSTR, test_fail

    # If we got here from U-mode test, we passed
    mv t0, x29                      # Read stage marker
    li t1, 5
    bne t0, t1, test_fail           # Only pass if coming from stage 5

    # All tests passed!
    TEST_PASS

handle_smode_ecall:
    # ECALL from S-mode (stage 4) - return to after_smode
    # This is the normal return path from S-mode test
    la t0, after_smode
    csrw mepc, t0
    mret

test_fail:
    TEST_FAIL

s_trap_handler:
    # Unexpected S-mode trap
    TEST_FAIL

TRAP_TEST_DATA_AREA
