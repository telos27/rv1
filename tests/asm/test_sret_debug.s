# Debug SRET SIE/SPIE behavior
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
    ENTER_SMODE_M smode1

smode1:
    # Read initial sstatus
    csrr a0, sstatus        # Save for debug

    # Clear SPIE (bit 5)
    li t0, MSTATUS_SPIE
    csrrc zero, sstatus, t0

    # Set SIE (bit 1)
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0

    # Set SPP=S (bit 8)
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Read sstatus before SRET
    csrr a1, sstatus        # Should have SIE=1, SPIE=0, SPP=1

    # Do SRET
    la t0, check1
    csrw sepc, t0
    sret

check1:
    # Read sstatus after SRET
    csrr a2, sstatus        # Should have SIE=0, SPIE=1, SPP=0

    # Check SIE (bit 1) - should be 0
    li t1, MSTATUS_SIE
    and t2, a2, t1
    bnez t2, fail           # SIE should be 0

    # Check SPIE (bit 5) - should be 1
    li t1, MSTATUS_SPIE
    and t2, a2, t1
    beqz t2, fail           # SPIE should be 1

    # Success
    TEST_PASS

fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
