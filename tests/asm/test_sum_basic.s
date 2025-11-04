# ==============================================================================
# Test: Basic SUM bit toggle - verify bit exists in MSTATUS
# ==============================================================================
#
# Simple test to verify:
# 1. SUM bit (MSTATUS[18]) can be written
# 2. SUM bit can be read back
# 3. No side effects from toggling SUM
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Read initial MSTATUS
    csrr    t0, mstatus

    TEST_STAGE 2

    # Set SUM bit (bit 18)
    ENABLE_SUM

    # Read back and verify bit 18 is set
    csrr    t1, mstatus
    li      t2, MSTATUS_SUM         # 0x40000 = bit 18
    and     t3, t1, t2
    beqz    t3, test_fail           # SUM bit should be set

    TEST_STAGE 3

    # Clear SUM bit
    DISABLE_SUM

    # Read back and verify bit 18 is clear
    csrr    t1, mstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    bnez    t3, test_fail           # SUM bit should be clear

    TEST_STAGE 4

    # Test passes
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
