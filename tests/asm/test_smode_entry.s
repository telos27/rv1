# Test S-mode entry and sstatus read
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

    TEST_STAGE 1

    # Read mstatus in M-mode
    csrr a0, mstatus

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    TEST_STAGE 2

    # Try to read mstatus in S-mode (should work - mstatus visible from S)
    csrr a1, mstatus

    # Try to read sstatus in S-mode (should work)
    csrr a2, sstatus

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    # If we trap, save the cause
    csrr a3, mcause
    TEST_FAIL

s_trap_handler:
    # If we trap in S-mode, save the cause
    csrr a4, scause  
    TEST_FAIL

TRAP_TEST_DATA_AREA
