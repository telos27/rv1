# Simple SRET test - verify basic S-mode entry and return
.include "tests/asm/include/priv_test_macros.s"

.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Test: Enter S-mode and return
    TEST_STAGE 1

    # Setup trap delegation
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    # We're in S-mode, try to return via SRET
    la t0, after_sret
    csrw sepc, t0

    # Execute SRET
    sret

after_sret:
    # If we got here, test passed
    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    # Unexpected M-mode trap
    TEST_FAIL

s_trap_handler:
    # Unexpected S-mode trap
    TEST_FAIL

TRAP_TEST_DATA_AREA
