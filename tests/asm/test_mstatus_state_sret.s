# Test 2.2: SRET State Transitions
# Purpose: Verify SRET correctly updates sstatus/mstatus state machine
# Tests: SIE←SPIE, SPIE←1, privilege←SPP, SPP←U

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: SRET with SPIE=0, SIE=1 → After SRET: SIE=0, SPIE=1
    #========================================================================
    TEST_STAGE 1

    # No delegation needed for stages 1-3 (all S-mode operations)
    csrw medeleg, zero
    csrw mideleg, zero

    # Enter S-mode first
    ENTER_SMODE_M smode_test1

smode_test1:
    # Setup: Clear SPIE, Set SIE (use sstatus in S-mode)
    li t0, MSTATUS_SPIE
    csrrc zero, sstatus, t0         # Clear SPIE
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0         # Set SIE

    # Set SPP = S so we stay in S-mode after SRET
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0         # Set SPP to S-mode

    # Set return address
    la t0, after_sret1
    csrw sepc, t0

    # Execute SRET
    sret

after_sret1:
    # Verify SIE is now 0 (copied from SPIE which was 0)
    EXPECT_BITS_CLEAR sstatus, MSTATUS_SIE, test_fail

    # Verify SPIE is now 1 (set to 1 by SRET)
    EXPECT_BITS_SET sstatus, MSTATUS_SPIE, test_fail

    #========================================================================
    # Test Case 2: SRET with SPIE=1, SIE=0 → After SRET: SIE=1, SPIE=1
    #========================================================================
    TEST_STAGE 2

    # Setup: Set SPIE, Clear SIE (use sstatus in S-mode)
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0         # Set SPIE
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0         # Clear SIE

    # Set SPP = S so we stay in S-mode after SRET
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0         # Set SPP to S-mode

    # Set return address
    la t0, after_sret2
    csrw sepc, t0

    # Execute SRET
    sret

after_sret2:
    # Verify SIE is now 1 (copied from SPIE which was 1)
    EXPECT_BITS_SET sstatus, MSTATUS_SIE, test_fail

    # Verify SPIE is now 1 (set to 1 by SRET)
    EXPECT_BITS_SET sstatus, MSTATUS_SPIE, test_fail

    #========================================================================
    # Test Case 3: SRET with SPP=S → privilege stays S
    #========================================================================
    TEST_STAGE 3

    # Setup: SPP = S-mode (1) - set using sstatus in S-mode
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0         # Set SPP to S-mode

    # Set return address
    la t0, after_sret3
    csrw sepc, t0

    # Execute SRET
    sret

after_sret3:
    # Verify we're still in S-mode by accessing S-mode CSR
    csrr t0, sstatus                # Should succeed in S-mode

    # Verify SPP is now U (per spec: SPP is set to U after SRET)
    # Read SPP field from sstatus
    csrr t0, sstatus
    li t1, MSTATUS_SPP
    and t2, t0, t1
    bnez t2, test_fail              # Should be 0 (U-mode)

    #========================================================================
    # Test Case 4: SRET with SPP=U → privilege becomes U
    #========================================================================
    TEST_STAGE 4

    # Need to return to M-mode to set up delegation
    ecall

mmode_stage4_setup:
    # Delegate illegal instruction exception to S-mode for U-mode test
    li t0, (1 << CAUSE_ILLEGAL_INSTR)
    csrw medeleg, t0

    # Enter S-mode to continue test
    ENTER_SMODE_M smode_test4

smode_test4:
    # Setup trap handler for U-mode test
    la t0, s_trap_handler_stage4
    csrw stvec, t0

    # Setup: SPP = U-mode (0) - clear SPP using sstatus
    li t0, MSTATUS_SPP
    csrrc zero, sstatus, t0         # Clear SPP to U-mode

    # Set return address to U-mode code
    la t0, umode_code
    csrw sepc, t0

    # Execute SRET
    sret

umode_code:
    # Verify we're in U-mode by attempting S-mode CSR access
    # This should trap with illegal instruction

    # Try to access S-mode CSR (should cause trap)
    csrr t0, sstatus

    # Should never reach here
    TEST_FAIL

s_trap_handler_stage4:
    # Verify cause is illegal instruction (U-mode can't access sstatus)
    EXPECT_CSR scause, CAUSE_ILLEGAL_INSTR, test_fail

    # Verify we're coming from stage 4
    mv t0, x29                      # Read stage marker
    li t1, 4
    bne t0, t1, test_fail

    # Stage 4 passed - return to M-mode to start stage 5
    # Use ECALL to get to M-mode handler which will start stage 5
    ecall

    #========================================================================
    # Test Case 5: Verify SRET clears mstatus.SPP (bit 8)
    #========================================================================
stage5_mmode_entry:
    TEST_STAGE 5

    # Clear delegation (stage 4 delegated illegal instruction)
    csrw medeleg, zero
    csrw mideleg, zero

    # Verify we're in M-mode by checking we can write mstatus
    csrr t0, mstatus
    csrw mstatus, t0

    # Enter S-mode to execute the SRET test
    ENTER_SMODE_M smode_test5

smode_test5:
    # Set SPP to S-mode using sstatus
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0         # Set SPP to S-mode (bit 8)

    # Verify SPP is set by reading back via sstatus
    csrr t0, sstatus
    li t1, MSTATUS_SPP
    and t2, t0, t1
    beqz t2, test_fail              # Should be set

    # Execute SRET with SPP=S (should stay in S-mode, but SPP→U)
    la t0, after_sret5
    csrw sepc, t0
    sret

after_sret5:
    # Now in S-mode after SRET
    # Verify SPP was cleared to U-mode by reading sstatus
    csrr t0, sstatus
    li t1, MSTATUS_SPP
    and t2, t0, t1
    bnez t2, test_fail              # Should be clear (U-mode = 0)

    # All tests passed!
    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    # Check trap cause
    csrr t0, mcause
    li t1, CAUSE_ECALL_S
    bne t0, t1, m_trap_unexpected

    # Check stage number to determine which transition
    mv t0, x29
    li t1, 3
    beq t0, t1, handle_stage3_to_4_transition

    li t1, 4
    beq t0, t1, handle_stage4_to_5_transition

    # Unexpected ECALL
    j m_trap_unexpected

handle_stage3_to_4_transition:
    # ECALL from end of stage 3 - set up delegation and go to stage 4
    la t0, mmode_stage4_setup
    csrw mepc, t0
    # Set MPP = M-mode so MRET returns to M-mode
    li t1, ~MSTATUS_MPP_MASK
    csrr t2, mstatus
    and t2, t2, t1              # Clear MPP bits
    li t1, (PRIV_M << MSTATUS_MPP_SHIFT)
    or t2, t2, t1               # Set MPP = 11 (M-mode)
    csrw mstatus, t2
    mret

handle_stage4_to_5_transition:
    # ECALL from S-mode trap handler at end of stage 4
    # Return to M-mode to start stage 5
    la t0, stage5_mmode_entry
    csrw mepc, t0
    # Set MPP = M-mode so MRET returns to M-mode
    li t1, ~MSTATUS_MPP_MASK
    csrr t2, mstatus
    and t2, t2, t1              # Clear MPP bits
    li t1, (PRIV_M << MSTATUS_MPP_SHIFT)
    or t2, t2, t1               # Set MPP = 11 (M-mode)
    csrw mstatus, t2
    mret

m_trap_unexpected:
    # Unexpected M-mode trap
    TEST_FAIL

s_trap_handler:
    # Default S-mode trap handler (not stage 4)
    TEST_FAIL

TRAP_TEST_DATA_AREA
