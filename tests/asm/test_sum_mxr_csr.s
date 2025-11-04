# ==============================================================================
# Test: Combined SUM and MXR CSR operations
# ==============================================================================
#
# Comprehensive test to verify:
# 1. SUM bit (MSTATUS[18]) and MXR bit (MSTATUS[19]) are independent
# 2. Both bits can be set simultaneously
# 3. Clearing one doesn't affect the other
# 4. Both bits can be cleared simultaneously
#
# This test is critical for xv6 as it needs to manage both bits independently
# during syscall handling and instruction fetch operations.
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Clear both bits initially
    li      t0, MSTATUS_SUM
    li      t1, MSTATUS_MXR
    or      t0, t0, t1
    csrrc   zero, mstatus, t0

    # Verify both are clear
    csrr    t2, mstatus
    and     t3, t2, t0
    bnez    t3, test_fail

    TEST_STAGE 2

    # Set SUM only
    li      t0, MSTATUS_SUM
    csrrs   zero, mstatus, t0

    # Verify SUM is set, MXR is clear
    csrr    t1, mstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    beqz    t3, test_fail           # SUM should be set

    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # MXR should be clear

    TEST_STAGE 3

    # Set MXR (SUM should remain set)
    li      t0, MSTATUS_MXR
    csrrs   zero, mstatus, t0

    # Verify both are now set
    csrr    t1, mstatus
    li      t0, MSTATUS_SUM
    li      t2, MSTATUS_MXR
    or      t0, t0, t2
    and     t3, t1, t0
    bne     t3, t0, test_fail       # Both should be set

    TEST_STAGE 4

    # Clear SUM only (MXR should remain set)
    li      t0, MSTATUS_SUM
    csrrc   zero, mstatus, t0

    # Verify SUM is clear, MXR is set
    csrr    t1, mstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    bnez    t3, test_fail           # SUM should be clear

    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # MXR should be set

    TEST_STAGE 5

    # Set SUM again (both should be set)
    li      t0, MSTATUS_SUM
    csrrs   zero, mstatus, t0

    # Verify both are set
    csrr    t1, mstatus
    li      t0, MSTATUS_SUM
    li      t2, MSTATUS_MXR
    or      t0, t0, t2
    and     t3, t1, t0
    bne     t3, t0, test_fail

    TEST_STAGE 6

    # Clear both bits simultaneously
    li      t0, MSTATUS_SUM
    li      t1, MSTATUS_MXR
    or      t0, t0, t1
    csrrc   zero, mstatus, t0

    # Verify both are clear
    csrr    t1, mstatus
    and     t3, t1, t0
    bnez    t3, test_fail

    TEST_STAGE 7

    # Set both bits simultaneously
    li      t0, MSTATUS_SUM
    li      t1, MSTATUS_MXR
    or      t0, t0, t1
    csrrs   zero, mstatus, t0

    # Verify both are set
    csrr    t1, mstatus
    and     t3, t1, t0
    bne     t3, t0, test_fail

    TEST_STAGE 8

    # Test passes
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
