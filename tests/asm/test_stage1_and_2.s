# Test stages 1 and 2 only
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Delegate to S-mode
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    # Enter S-mode
    ENTER_SMODE_M smode_test1

smode_test1:
    TEST_STAGE 1

    # Stage 1: SRET with SPIE=0, SIE=1 → After SRET: SIE=0, SPIE=1
    # Setup: Clear SPIE, Set SIE
    li t0, MSTATUS_SPIE
    csrrc zero, sstatus, t0
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0

    # Set SPP = S
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Set return address
    la t0, after_sret1
    csrw sepc, t0

    # Execute SRET
    sret

after_sret1:
    # Save sstatus for inspection
    csrr s0, sstatus

    # Verify SIE is now 0
    EXPECT_BITS_CLEAR sstatus, MSTATUS_SIE, test_fail

    # Verify SPIE is now 1
    EXPECT_BITS_SET sstatus, MSTATUS_SPIE, test_fail

    TEST_STAGE 2

    # Stage 2: SRET with SPIE=1, SIE=0 → After SRET: SIE=1, SPIE=1
    # Setup: Set SPIE, Clear SIE
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0

    # Set SPP = S
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Set return address
    la t0, after_sret2
    csrw sepc, t0

    # Execute SRET
    sret

after_sret2:
    # Save sstatus for inspection
    csrr s1, sstatus

    # Verify SIE is now 1
    EXPECT_BITS_SET sstatus, MSTATUS_SIE, test_fail

    # Verify SPIE is now 1
    EXPECT_BITS_SET sstatus, MSTATUS_SPIE, test_fail

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
