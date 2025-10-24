# Trace mstatus through SRET
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
    # Read initial mstatus in S-mode
    csrr s0, mstatus

    # Setup: Set SPIE=1
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0
    
    # Read mstatus after setting SPIE
    csrr s1, mstatus
    
    # Clear SIE=0
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0

    # Read mstatus after clearing SIE
    csrr s2, mstatus

    # Set SPP=S
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Read mstatus before SRET
    csrr s3, mstatus

    # Set return address
    la t0, after_sret
    csrw sepc, t0

    # Execute SRET
    sret

after_sret:
    # Read mstatus after SRET
    csrr s4, mstatus
    
    # Read sstatus after SRET
    csrr s5, sstatus

    # Check: s4 should have SIE=1 (bit 1) and SPIE=1 (bit 5)
    # Extract SIE
    li t0, MSTATUS_SIE
    and a0, s4, t0
    srli a0, a0, 1
    
    # Extract SPIE
    li t0, MSTATUS_SPIE
    and a1, s4, t0
    srli a1, a1, 5

    # Both should be 1
    li t0, 1
    bne a0, t0, test_fail
    bne a1, t0, test_fail

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
