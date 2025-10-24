# Minimal SRET test - just execute SRET and check SPIE
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Delegate
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    # Clear everything in sstatus first
    csrw sstatus, zero

    # Read sstatus (should be all zeros)
    csrr s0, sstatus

    # Set return address
    la t0, after_sret
    csrw sepc, t0
    
    # Set SPP=S to stay in S-mode
    li t0, MSTATUS_SPP
    csrw sstatus, t0

    # Execute SRET (should set SPIE=1, SIE=0, SPP=0)
    sret

after_sret:
    # Read sstatus immediately after SRET
    csrr s1, sstatus

    # s1 should have SPIE=1 (bit 5) = 0x20
    li t0, 0x20
    beq s1, t0, test_pass

    TEST_FAIL

test_pass:
    TEST_PASS

m_trap_handler:
    TEST_FAIL

s_trap_handler:
    TEST_FAIL

TRAP_TEST_DATA_AREA
