# Test 2.5: Interrupt Enable Verification
# Purpose: Verify MIE/SIE/MPIE/SPIE enable/disable mechanisms
# Tests: Individual interrupt enable bits, global enable behavior

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: MIE enable/disable
    #========================================================================
    TEST_STAGE 1

    # Verify we can set MIE
    ENABLE_MIE
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # Verify we can clear MIE
    DISABLE_MIE
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Set it again
    ENABLE_MIE
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    #========================================================================
    # Test Case 2: MPIE enable/disable
    #========================================================================
    TEST_STAGE 2

    # Verify we can set MPIE
    ENABLE_MPIE
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Verify we can clear MPIE
    DISABLE_MPIE
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MPIE, test_fail

    # Set it again
    ENABLE_MPIE
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    #========================================================================
    # Test Case 3: MIE preserved across trap when MPIE mechanism works
    #========================================================================
    TEST_STAGE 3

    # Start with MIE=1
    ENABLE_MIE

    # Take a trap
    ecall

after_trap1:
    # After MRET with MPIE=1 (set during trap):
    # MIE should be 1 (restored from MPIE)
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # MPIE should be 1 (set by MRET)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    #========================================================================
    # Test Case 4: MIE cleared on trap entry, restored on MRET
    #========================================================================
    TEST_STAGE 4

    # Start with MIE=1
    ENABLE_MIE
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # Take a trap (will verify MIE=0 in handler)
    ecall

after_trap2:
    # After MRET: MIE should be 1 again (restored from MPIE)
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    #========================================================================
    # Test Case 5: MPIE independence from MIE
    #========================================================================
    TEST_STAGE 5

    # Set MPIE=1, MIE=0
    ENABLE_MPIE
    DISABLE_MIE

    # Verify both
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Set MPIE=0, MIE=1
    DISABLE_MPIE
    ENABLE_MIE

    # Verify both
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MPIE, test_fail
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    #========================================================================
    # Test Case 6: SIE enable/disable (in S-mode)
    #========================================================================
    TEST_STAGE 6

    # Clear delegation to stay in M-mode for mode transition
    csrw medeleg, zero
    csrw mideleg, zero

    # Enter S-mode
    ENTER_SMODE_M smode_test

smode_test:
    # In S-mode: test SIE
    # Set SIE
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0

    # Verify SIE is set
    csrr t0, sstatus
    li t1, MSTATUS_SIE
    and t2, t0, t1
    beqz t2, test_fail

    # Clear SIE
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0

    # Verify SIE is clear
    csrr t0, sstatus
    li t1, MSTATUS_SIE
    and t2, t0, t1
    bnez t2, test_fail

    # All tests passed!
    TEST_PASS

# ==============================================================================
# Trap Handlers
# ==============================================================================

m_trap_handler:
    # Dispatcher based on stage
    mv t0, x29
    li t1, 3
    beq t0, t1, stage3_handler
    li t1, 4
    beq t0, t1, stage4_handler
    j test_fail

stage3_handler:
    # Stage 3: Verify trap entry behavior
    # MIE should be 0 (cleared on trap entry)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # MPIE should be 1 (saved from MIE=1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Return
    la t0, after_trap1
    csrw mepc, t0
    mret

stage4_handler:
    # Stage 4: Verify MIE is 0 during trap handler
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # MPIE should be 1 (saved from MIE=1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Return
    la t0, after_trap2
    csrw mepc, t0
    mret

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
