# Test 3.4: Interrupt Pending Bits
# Purpose: Verify mip/sip pending bit behavior
# Tests: Software interrupt pending bits, mip/sip relationship

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: Machine Software Interrupt Pending (MSIP) - bit 3
    #========================================================================
    TEST_STAGE 1

    # Clear mip
    csrw mip, zero

    # Set MSIP (bit 3)
    li t0, (1 << 3)
    csrw mip, t0

    # Read back and verify MSIP is set
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear MSIP
    csrw mip, zero

    # Verify it's cleared
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail

    #========================================================================
    # Test Case 2: Supervisor Software Interrupt Pending (SSIP) - bit 1
    #========================================================================
    TEST_STAGE 2

    # Set SSIP (bit 1)
    li t0, (1 << 1)
    csrw mip, t0

    # Read back via mip
    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear it
    csrw mip, zero

    #========================================================================
    # Test Case 3: sip shows subset of mip (S-mode view)
    #========================================================================
    TEST_STAGE 3

    # Set multiple interrupt pending bits in mip
    # MSIP (bit 3) + SSIP (bit 1)
    li t0, ((1 << 3) | (1 << 1))
    csrw mip, t0

    # Read sip (should only show SSIP bit 1, not MSIP bit 3)
    # sip masks to bits [9,5,1] per spec
    csrr t1, sip

    # Verify SSIP is visible in sip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Verify MSIP (bit 3) is NOT visible in sip
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail

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
    # Test Case 5: Multiple pending bits
    #========================================================================
    TEST_STAGE 5

    # Set MSIP and SSIP simultaneously
    li t0, ((1 << 3) | (1 << 1))
    csrw mip, t0

    # Verify both are set
    csrr t1, mip
    li t2, ((1 << 3) | (1 << 1))
    and t3, t1, t2
    bne t3, t2, test_fail

    # Clear SSIP only (via sip)
    csrw sip, zero

    # Verify MSIP still set, SSIP cleared
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    beqz t3, test_fail          # MSIP should still be set

    csrr t1, mip
    li t2, (1 << 1)
    and t3, t1, t2
    bnez t3, test_fail          # SSIP should be cleared

    # All tests passed!
    TEST_PASS

m_trap_handler:
    j test_fail

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
