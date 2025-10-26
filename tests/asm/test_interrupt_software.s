# Test 3.1: Software Interrupt CSRs
# Purpose: Verify software interrupt pending/enable register behavior
# Tests: MSIP/SSIP pending bits, MSIE/SSIE enable bits interaction
# Note: This test does NOT require actual interrupt delivery (CPU doesn't implement that yet)

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: MSIP and MSIE interaction
    #========================================================================
    TEST_STAGE 1

    # Clear both mip and mie
    csrw mip, zero
    csrw mie, zero

    # Set MSIP (bit 3) in mip
    li t0, (1 << 3)
    csrw mip, t0

    # Set MSIE (bit 3) in mie
    li t0, (1 << 3)
    csrw mie, t0

    # Verify both are set
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    beqz t3, test_fail

    csrr t1, mie
    and t3, t1, t2
    beqz t3, test_fail

    # Clear both
    csrw mip, zero
    csrw mie, zero

    #========================================================================
    # Test Case 2: SSIP and SSIE interaction
    #========================================================================
    TEST_STAGE 2

    # Set SSIP (bit 1) in mip/sip
    li t0, (1 << 1)
    csrw sip, t0

    # Set SSIE (bit 1) in mie/sie
    li t0, (1 << 1)
    csrw sie, t0

    # Verify both visible in sip/sie
    csrr t1, sip
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    csrr t1, sie
    and t3, t1, t2
    beqz t3, test_fail

    # Clear both
    csrw sip, zero
    csrw sie, zero

    #========================================================================
    # Test Case 3: Interrupt delegation register (mideleg)
    #========================================================================
    TEST_STAGE 3

    # Clear mideleg
    csrw mideleg, zero

    # Set delegation for SSIP (bit 1)
    li t0, (1 << 1)
    csrw mideleg, t0

    # Read back
    csrr t1, mideleg
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Set delegation for STIP (bit 5)
    li t0, ((1 << 5) | (1 << 1))
    csrw mideleg, t0

    # Read back - both should be set
    csrr t1, mideleg
    li t2, ((1 << 5) | (1 << 1))
    and t3, t1, t2
    bne t3, t2, test_fail

    # Clear delegation
    csrw mideleg, zero

    # All tests passed!
    TEST_PASS

# ==============================================================================
# Trap Handlers
# ==============================================================================

m_trap_handler:
    j test_fail

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
