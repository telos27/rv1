# Test 3.5: Interrupt Masking
# Purpose: Verify mie/sie interrupt enable bits
# Tests: Individual interrupt enable control, global MIE/SIE

.include "tests/asm/include/priv_test_macros.s"

# Disable compressed instructions to avoid PC misalignment issues
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    #========================================================================
    # Test Case 1: Machine Timer Interrupt Enable (MTIE) - bit 7
    #========================================================================
    TEST_STAGE 1

    # Clear mie
    csrw mie, zero

    # Set MTIE (bit 7)
    li t0, (1 << 7)
    csrw mie, t0

    # Read back and verify MTIE is set
    csrr t1, mie
    li t2, (1 << 7)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear MTIE
    csrw mie, zero

    # Verify it's cleared
    csrr t1, mie
    li t2, (1 << 7)
    and t3, t1, t2
    bnez t3, test_fail

    #========================================================================
    # Test Case 2: Machine Software Interrupt Enable (MSIE) - bit 3
    #========================================================================
    TEST_STAGE 2

    # Set MSIE (bit 3)
    li t0, (1 << 3)
    csrw mie, t0

    # Read back
    csrr t1, mie
    li t2, (1 << 3)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear it
    csrw mie, zero

    #========================================================================
    # Test Case 3: Machine External Interrupt Enable (MEIE) - bit 11
    #========================================================================
    TEST_STAGE 3

    # Set MEIE (bit 11)
    li t0, (1 << 11)
    csrw mie, t0

    # Read back
    csrr t1, mie
    li t2, (1 << 11)
    and t3, t1, t2
    beqz t3, test_fail

    # Clear it
    csrw mie, zero

    #========================================================================
    # Test Case 4: Supervisor Timer Interrupt Enable (STIE) - bit 5
    #========================================================================
    TEST_STAGE 4

    # Set STIE via mie
    li t0, (1 << 5)
    csrw mie, t0

    # Read back via sie (should be visible)
    csrr t1, sie
    li t2, (1 << 5)
    and t3, t1, t2
    beqz t3, test_fail

    # Also visible in mie
    csrr t1, mie
    and t3, t1, t2
    beqz t3, test_fail

    # Clear via sie
    csrw sie, zero

    # Verify cleared in mie
    csrr t1, mie
    and t3, t1, t2
    bnez t3, test_fail

    #========================================================================
    # Test Case 5: Multiple interrupt enables
    #========================================================================
    TEST_STAGE 5

    # Set MTIE, MSIE, MEIE simultaneously
    li t0, ((1 << 11) | (1 << 7) | (1 << 3))
    csrw mie, t0

    # Verify all three are set
    csrr t1, mie
    li t2, ((1 << 11) | (1 << 7) | (1 << 3))
    and t3, t1, t2
    bne t3, t2, test_fail

    # Clear MTIE only
    li t0, ~(1 << 7)
    csrr t1, mie
    and t1, t1, t0
    csrw mie, t1

    # Verify MSIE and MEIE still set, MTIE cleared
    csrr t1, mie
    li t2, (1 << 7)
    and t3, t1, t2
    bnez t3, test_fail          # MTIE should be cleared

    csrr t1, mie
    li t2, ((1 << 11) | (1 << 3))
    and t3, t1, t2
    bne t3, t2, test_fail       # MSIE and MEIE should still be set

    #========================================================================
    # Test Case 6: sie shows subset of mie
    #========================================================================
    TEST_STAGE 6

    # Set both M-mode and S-mode interrupt enables
    # MTIE (7), STIE (5), MSIE (3), SSIE (1)
    li t0, ((1 << 7) | (1 << 5) | (1 << 3) | (1 << 1))
    csrw mie, t0

    # Read sie - should only show STIE (5) and SSIE (1), not MTIE/MSIE
    csrr t1, sie

    # Verify STIE visible
    li t2, (1 << 5)
    and t3, t1, t2
    beqz t3, test_fail

    # Verify SSIE visible
    li t2, (1 << 1)
    and t3, t1, t2
    beqz t3, test_fail

    # Verify MTIE NOT visible
    li t2, (1 << 7)
    and t3, t1, t2
    bnez t3, test_fail

    # Verify MSIE NOT visible
    li t2, (1 << 3)
    and t3, t1, t2
    bnez t3, test_fail

    # All tests passed!
    TEST_PASS

m_trap_handler:
    j test_fail

s_trap_handler:
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
