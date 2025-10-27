# Test 3.4: Interrupt Pending Bits
# Purpose: Verify mip/sip pending bit behavior
# Tests: SSIP (software-writable), MSIP/MTIP (hardware-driven, read-only)
# Note: After CLINT integration, MSIP (bit 3) and MTIP (bit 7) are READ-ONLY

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: MSIP/MTIP are READ-ONLY (hardware-driven by CLINT)
    #========================================================================
    TEST_STAGE 1

    # Clear mip
    csrw mip, zero

    # Try to set MSIP (bit 3) - should be ignored (read-only)
    li t0, (1 << 3)
    csrw mip, t0

    # Read back - MSIP should NOT be set (it's hardware-driven)
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail          # Test fails if MSIP got set

    # Try to set MTIP (bit 7) - should be ignored (read-only)
    li t0, (1 << 7)
    csrw mip, t0

    # Read back - MTIP should NOT be set (it's hardware-driven)
    csrr t1, mip
    li t2, (1 << 7)
    and t3, t1, t2
    bnez t3, test_fail          # Test fails if MTIP got set

    #========================================================================
    # Test Case 2: SSIP (bit 1) IS software-writable
    #========================================================================
    TEST_STAGE 2

    # Clear mip
    csrw mip, zero

    # Set SSIP (bit 1) - this SHOULD work (software-writable)
    li t0, (1 << 1)
    csrw mip, t0

    # Read back via mip - SSIP should be set
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail          # Test fails if SSIP not set

    # Clear it
    csrw mip, zero

    # Verify cleared
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    bnez t3, test_fail          # Test fails if SSIP still set

    #========================================================================
    # Test Case 3: sip shows subset of mip (S-mode view)
    #========================================================================
    TEST_STAGE 3

    # Set SSIP in mip
    li t0, (1 << 1)
    csrw mip, t0

    # Read sip - SSIP should be visible (bit 1 is in S-mode mask)
    # sip masks to bits [9,5,1] per spec
    csrr t1, sip

    # Verify SSIP is visible in sip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Verify MSIP (bit 3) is NOT visible in sip (M-mode only)
    # Even if MSIP were set, sip wouldn't show it
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail          # Bit 3 should never appear in sip

    # Clear mip
    csrw mip, zero

    #========================================================================
    # Test Case 4: Write to sip affects mip
    #========================================================================
    TEST_STAGE 4

    # Clear both
    csrw mip, zero
    csrw sip, zero

    # Write SSIP via sip
    li t0, (1 << 1)
    csrw sip, t0

    # Verify visible in mip
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Verify visible in sip
    csrr t1, sip
    and t3, t1, t2
    beqz t3, test_fail

    # Clear via sip
    csrw sip, zero

    # Verify cleared in mip
    csrr t1, mip
    and t3, t1, t2
    bnez t3, test_fail

    #========================================================================
    # Test Case 5: Clearing via mip vs sip
    #========================================================================
    TEST_STAGE 5

    # Set SSIP via mip
    li t0, (1 << 1)
    csrw mip, t0

    # Verify set
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear SSIP via sip
    csrw sip, zero

    # Verify cleared in both mip and sip
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    bnez t3, test_fail          # SSIP should be cleared

    csrr t1, sip
    and t3, t1, t2
    bnez t3, test_fail          # SSIP should be cleared in sip too

    # All tests passed!
    TEST_PASS

m_trap_handler:
    j test_fail

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
