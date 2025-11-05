# Simple test to verify SUM bit behavior without VM complexity
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.equ MSTATUS_SUM_BIT, 18
.equ SSTATUS_SUM_BIT, 18

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Start in M-mode, ensure SUM=0
    li      t0, (1 << MSTATUS_SUM_BIT)
    csrc    mstatus, t0

    # Verify SUM=0 in MSTATUS
    csrr    t1, mstatus
    and     t2, t1, t0
    bnez    t2, test_fail

    TEST_STAGE 2

    # Enter S-mode
    SET_STVEC_DIRECT s_trap
    ENTER_SMODE_M smode_entry

smode_entry:
    TEST_STAGE 3

    # Verify SUM=0 in SSTATUS
    csrr    t0, sstatus
    li      t1, (1 << SSTATUS_SUM_BIT)
    and     t2, t0, t1
    bnez    t2, test_fail

    TEST_STAGE 4

    # Set SUM=1
    li      t0, (1 << SSTATUS_SUM_BIT)
    csrs    sstatus, t0

    # Verify SUM=1
    csrr    t1, sstatus
    and     t2, t1, t0
    beqz    t2, test_fail

    TEST_STAGE 5

    # Clear SUM
    li      t0, (1 << SSTATUS_SUM_BIT)
    csrc    sstatus, t0

    # Verify SUM=0
    csrr    t1, sstatus
    and     t2, t1, t0
    bnez    t2, test_fail

    TEST_STAGE 6
    TEST_PASS

test_fail:
    TEST_FAIL

s_trap:
    j test_fail

TRAP_TEST_DATA_AREA
