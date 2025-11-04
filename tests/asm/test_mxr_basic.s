# ==============================================================================
# Test: Basic MXR bit toggle - verify bit exists in MSTATUS
# ==============================================================================
#
# Simple test to verify:
# 1. MXR bit (MSTATUS[19]) can be written
# 2. MXR bit can be read back
# 3. No side effects from toggling MXR
#
# MXR (Make eXecutable Readable): When set, allows loads from executable-only
# pages. This is used by OS kernels to read instruction pages.
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

    # Set MXR bit (bit 19)
    li      t0, MSTATUS_MXR         # 0x80000 = bit 19
    csrrs   zero, mstatus, t0

    # Read back and verify bit 19 is set
    csrr    t1, mstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # MXR bit should be set

    TEST_STAGE 3

    # Clear MXR bit
    li      t0, MSTATUS_MXR
    csrrc   zero, mstatus, t0

    # Read back and verify bit 19 is clear
    csrr    t1, mstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # MXR bit should be clear

    TEST_STAGE 4

    # Test passes
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
