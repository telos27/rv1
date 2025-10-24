# Test SRET SIE/SPIE handling
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

    # Test 1: SPIE=0, SIE=1 → After SRET: SIE=0, SPIE=1
    TEST_STAGE 1

    # Enter S-mode
    ENTER_SMODE_M smode1

smode1:
    # Clear SPIE
    li t0, MSTATUS_SPIE
    csrrc zero, sstatus, t0

    # Set SIE
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0

    # Set SPP=S to stay in S-mode
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Do SRET
    la t0, check1
    csrw sepc, t0
    sret

check1:
    # Check SIE is 0 (from SPIE)
    csrr t0, sstatus
    li t1, MSTATUS_SIE
    and t2, t0, t1
    bnez t2, fail                   # Should be 0

    # Check SPIE is 1 (set by SRET)
    csrr t0, sstatus
    li t1, MSTATUS_SPIE
    and t2, t0, t1
    beqz t2, fail                   # Should be 1

    # Test passed
    TEST_PASS

fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
