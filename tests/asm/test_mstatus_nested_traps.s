# Test 2.4: Sequential Trap Handling
# Purpose: Verify mstatus state across multiple sequential traps
# Tests: MPIE/MIE/MPP behavior across multiple trap/return cycles

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: Multiple traps preserve and restore state correctly
    #========================================================================
    TEST_STAGE 1

    # Setup initial state: MIE=1, MPIE=1
    ENABLE_MIE
    ENABLE_MPIE

    # First trap
    ecall

after_trap1:
    # After first MRET: MIE should be 1 (restored from MPIE)
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # MPIE should be 1 (set by MRET)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Take second trap with same state
    ecall

after_trap2:
    # After second MRET: MIE should still be 1
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # MPIE should still be 1
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    #========================================================================
    # Test Case 2: Trap sequence with changing MIE
    #========================================================================
    TEST_STAGE 2

    # Start with MIE=0
    DISABLE_MIE

    # First trap
    ecall

after_trap3:
    # MIE should be 0 (restored from MPIE which was 0)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Now set MIE=1 for next trap
    ENABLE_MIE

    # Second trap
    ecall

after_trap4:
    # MIE should be 1 (restored from MPIE which was 1)
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    #========================================================================
    # Test Case 3: MPP preservation across multiple traps
    #========================================================================
    TEST_STAGE 3

    # Set MPP to S-mode
    SET_MPP PRIV_S

    # First trap (should save M-mode as MPP)
    ecall

after_trap5:
    # After MRET, MPP should be U (reset by MRET)
    EXPECT_MPP PRIV_U, test_fail

    # Set MPP to S again
    SET_MPP PRIV_S

    # Second trap
    ecall

after_trap6:
    # Again, MPP should be U after MRET
    EXPECT_MPP PRIV_U, test_fail

    # All tests passed!
    TEST_PASS

# ==============================================================================
# Trap Handlers
# ==============================================================================

m_trap_handler:
    # Dispatcher based on stage
    mv t0, x29
    li t1, 1
    beq t0, t1, stage1_handler
    li t1, 2
    beq t0, t1, stage2_handler
    li t1, 3
    beq t0, t1, stage3_handler
    j test_fail

stage1_handler:
    # Check which trap we're in by looking at mepc
    csrr t0, mepc
    la t1, after_trap1
    addi t1, t1, -4                 # Point to ECALL before after_trap1
    beq t0, t1, stage1_trap1

    # Must be second trap (before after_trap2)
    j stage1_trap2

stage1_trap1:
    # First trap in stage 1
    # Verify MPIE=1 (from MIE=1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE=0 (cleared on trap entry)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return to after_trap1
    la t0, after_trap1
    csrw mepc, t0
    mret

stage1_trap2:
    # Second trap in stage 1
    # Verify MPIE=1 (from MIE=1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE=0 (cleared on trap entry)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return to after_trap2
    la t0, after_trap2
    csrw mepc, t0
    mret

stage2_handler:
    # Check which trap we're in
    csrr t0, mepc
    la t1, after_trap3
    addi t1, t1, -4
    beq t0, t1, stage2_trap1

    # Must be second trap
    j stage2_trap2

stage2_trap1:
    # First trap: MIE was 0
    # Verify MPIE=0 (from MIE=0)
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE=0
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return
    la t0, after_trap3
    csrw mepc, t0
    mret

stage2_trap2:
    # Second trap: MIE was 1
    # Verify MPIE=1 (from MIE=1)
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    # Verify MIE=0
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail

    # Return
    la t0, after_trap4
    csrw mepc, t0
    mret

stage3_handler:
    # Check which trap we're in
    csrr t0, mepc
    la t1, after_trap5
    addi t1, t1, -4
    beq t0, t1, stage3_trap1

    # Must be second trap
    j stage3_trap2

stage3_trap1:
    # First trap: MPP was S before trap
    # Verify MPP=M (trap from M-mode)
    EXPECT_MPP PRIV_M, test_fail

    # Return
    la t0, after_trap5
    csrw mepc, t0
    mret

stage3_trap2:
    # Second trap: MPP was S before trap
    # Verify MPP=M (trap from M-mode)
    EXPECT_MPP PRIV_M, test_fail

    # Return
    la t0, after_trap6
    csrw mepc, t0
    mret

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
