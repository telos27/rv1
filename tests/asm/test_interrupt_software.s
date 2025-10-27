# Test 3.1: Software Interrupt CSRs
# Purpose: Verify software interrupt pending/enable register behavior
# Tests: SSIP pending bit (writable), SSIE enable bit, mideleg
# Note: MSIP (bit 3) and MTIP (bit 7) in mip are READ-ONLY (hardware-driven by CLINT)
#       This test focuses on SSIP (bit 1) which IS software-writable via sip

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: Verify MSIP/MTIP are READ-ONLY (hardware-driven)
    #========================================================================
    TEST_STAGE 1

    # Try to set MSIP (bit 3) in mip - should be ignored (read-only)
    csrw mip, zero
    li t0, (1 << 3)          # MSIP bit
    csrw mip, t0
    csrr t1, mip
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail       # MSIP should NOT be set (read-only)

    # Try to set MTIP (bit 7) in mip - should be ignored (read-only)
    li t0, (1 << 7)          # MTIP bit
    csrw mip, t0
    csrr t1, mip
    li t2, (1 << 7)
    and t3, t1, t2
    bnez t3, test_fail       # MTIP should NOT be set (read-only)

    # MSIE in mie IS writable (it's an enable bit, not pending)
    li t0, (1 << 3)          # MSIE bit
    csrw mie, t0
    csrr t1, mie
    and t3, t1, t0
    beqz t3, test_fail       # MSIE should be set

    # Clear mie
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

    # Set delegation for STIP (bit 5) and SEIP (bit 9)
    li t0, ((1 << 9) | (1 << 5) | (1 << 1))
    csrw mideleg, t0

    # Read back - all should be set
    csrr t1, mideleg
    li t2, ((1 << 9) | (1 << 5) | (1 << 1))
    and t3, t1, t2
    bne t3, t2, test_fail

    # Clear delegation
    csrw mideleg, zero

    # Verify cleared
    csrr t1, mideleg
    bnez t1, test_fail

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
