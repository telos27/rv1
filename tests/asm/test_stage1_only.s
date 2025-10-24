# Test stage 1 only: SPIE=0, SIE=1 → SRET → SIE=0, SPIE=1
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
    ENTER_SMODE_M smode_test1

smode_test1:
    # Setup: Clear SPIE=0, Set SIE=1
    li t0, MSTATUS_SPIE
    csrrc zero, sstatus, t0
    
    li t0, MSTATUS_SIE
    csrrs zero, sstatus, t0

    # Read sstatus before SRET
    csrr s0, sstatus

    # Set SPP = S
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Set return address
    la t0, after_sret1
    csrw sepc, t0

    # Execute SRET
    sret

after_sret1:
    # Read sstatus after SRET
    csrr s1, sstatus

    # Extract SIE (should be 0)
    li t0, MSTATUS_SIE
    and a0, s1, t0
    srli a0, a0, 1

    # Extract SPIE (should be 1)
    li t0, MSTATUS_SPIE
    and a1, s1, t0
    srli a1, a1, 5

    # Check: SIE should be 0
    bnez a0, test_fail

    # Check: SPIE should be 1
    li t0, 1
    bne a1, t0, test_fail

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
