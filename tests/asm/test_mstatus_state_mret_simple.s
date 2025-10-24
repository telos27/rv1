# Simple test for MRET state transitions
.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # TEST 1: MRET with MPIE=0, MIE=1 → After MRET: MIE=0, MPIE=1
    li t0, MSTATUS_MPIE
    csrrc zero, mstatus, t0         # Clear MPIE
    li t0, MSTATUS_MIE
    csrrs zero, mstatus, t0         # Set MIE

    la t0, after_mret1
    csrw mepc, t0
    mret

after_mret1:
    # Read mstatus for inspection
    csrr t0, mstatus

    # Verify MIE is now 0
    EXPECT_BITS_CLEAR mstatus, MSTATUS_MIE, test_fail_mie

    # Verify MPIE is now 1
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail_mpie

    # TEST 2: MRET with MPIE=1, MIE=0 → After MRET: MIE=1, MPIE=1
    li t0, MSTATUS_MPIE
    csrrs zero, mstatus, t0         # Set MPIE
    li t0, MSTATUS_MIE
    csrrc zero, mstatus, t0         # Clear MIE

    la t0, after_mret2
    csrw mepc, t0
    mret

after_mret2:
    # Verify MIE is now 1
    EXPECT_BITS_SET mstatus, MSTATUS_MIE, test_fail

    # Verify MPIE is still 1
    EXPECT_BITS_SET mstatus, MSTATUS_MPIE, test_fail

    TEST_PASS

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

test_fail:
    TEST_FAIL

test_fail_mie:
    li t3, 1
    TEST_FAIL

test_fail_mpie:
    li t3, 2
    TEST_FAIL

TRAP_TEST_DATA_AREA
