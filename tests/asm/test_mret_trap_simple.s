# Simple test: MRET in U-mode should trap

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Enter U-mode
    ENTER_UMODE_M try_mret

try_mret:
    # Try MRET from U-mode - should trap
    mret
    # Should not reach here
    TEST_FAIL

m_trap_handler:
    # Check mcause = 2 (illegal instruction)
    csrr t0, mcause
    li t1, 2
    bne t0, t1, test_fail

    # Success!
    TEST_PASS

test_fail:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
