# Test only stage 2 of SRET test
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
    # Stage 2: SRET with SPIE=1, SIE=0 → After SRET: SIE=1, SPIE=1
    
    # Setup: Set SPIE=1, Clear SIE=0
    li t0, MSTATUS_SPIE
    csrrs zero, sstatus, t0         # Set SPIE
    li t0, MSTATUS_SIE
    csrrc zero, sstatus, t0         # Clear SIE

    # Set SPP=S to stay in S-mode
    li t0, MSTATUS_SPP
    csrrs zero, sstatus, t0

    # Set return address
    la t0, after_sret
    csrw sepc, t0

    # Execute SRET
    sret

after_sret:
    # Read sstatus
    csrr a0, sstatus
    
    # Check SIE (bit 1) - should be 1
    li t0, MSTATUS_SIE
    and t1, a0, t0
    beqz t1, test_fail

    # Check SPIE (bit 5) - should be 1
    li t0, MSTATUS_SPIE
    and t1, a0, t0
    beqz t1, test_fail

    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
