# Test marker mechanism
.include "tests/asm/include/priv_test_macros.s"

.option norvc

.section .text
.globl _start

_start:
    # Just call TEST_PASS
    TEST_PASS

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
