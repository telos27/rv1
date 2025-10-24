# Test SRET SIE/SPIE updates
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
    ENTER_SMODE_M smode_code

smode_code:
    # Setup: SPIE=1, SIE=0
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0         # Set SPIE
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0         # Clear SIE

    # Read sstatus before SRET
    csrr a0, sstatus                # Save to a0

    # Set SPP=S to stay in S-mode
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Set return address
    la t0, after_sret
    csrw sepc, t0

    # Execute SRET
    sret

after_sret:
    # Read sstatus after SRET
    csrr a1, sstatus                # Save to a1

    # Check SIE bit (should be 1, from SPIE)
    li t0, MSTATUS_SIE
    and t1, a1, t0
    beqz t1, test_fail              # Fail if SIE=0

    # Check SPIE bit (should be 1, set by SRET)
    li t0, MSTATUS_SPIE
    and t1, a1, t0
    beqz t1, test_fail              # Fail if SPIE=0

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
