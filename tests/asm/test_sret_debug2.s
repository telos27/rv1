# Debug SRET - check each step
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    TEST_STAGE 1  # Should see x29=1

    # Delegate to S-mode
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    TEST_STAGE 2  # Should see x29=2

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    TEST_STAGE 3  # Should see x29=3 if we reach S-mode

    # Try to read sstatus
    csrr t0, sstatus
    # Save it to t3 for inspection
    mv t3, t0

    TEST_STAGE 4  # Should see x29=4

    # Try to write SPIE=1, SIE=0
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0
    
    TEST_STAGE 5  # Should see x29=5

    li t0, MSTATUS_SIE  
    csrrc zero, sstatus, t0

    TEST_STAGE 6  # Should see x29=6

    # Read back sstatus
    csrr t4, sstatus

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
