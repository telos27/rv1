# Debug test - just check what MRET does to mstatus
.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Clear MPIE, Set MIE
    li t0, MSTATUS_MPIE              # t0 = 0x80 (bit 7)
    csrrc zero, mstatus, t0          # Clear MPIE
    li t0, MSTATUS_MIE                # t0 = 0x08 (bit 3)
    csrrs zero, mstatus, t0          # Set MIE

    # Read mstatus before MRET
    csrr s0, mstatus                 # s0 = mstatus before

    # Do MRET
    la t0, after_mret
    csrw mepc, t0
    mret

after_mret:
    # Read mstatus after MRET
    csrr s1, mstatus                 # s1 = mstatus after

    # Store values for inspection (s0 = before, s1 = after)
    # Just exit
    TEST_PASS

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
