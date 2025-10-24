# Minimal test to debug SRET SPIE update issue
# Tests whether SRET correctly sets SPIE=1 when it was 0 before SRET

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    # Initialize test framework
    li x28, 0xF15BAD00    # Initialize TEST_FAIL marker
    li x29, 0             # Stage counter

    # Delegate all traps to S-mode
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    # Enter S-mode from M-mode
    # Set MPP = S-mode (01)
    li t0, (1 << 11)      # MPP bits [12:11] = 01 (S-mode)
    csrrs zero, mstatus, t0

    # Set MPIE = 1
    li t0, (1 << 7)
    csrrs zero, mstatus, t0

    # Set return address to S-mode code
    la t0, smode_start
    csrw mepc, t0

    # Execute MRET to enter S-mode
    mret

smode_start:
    # Now in S-mode
    # Stage 1: Test SRET with SPIE=0 before SRET

    # Clear SPIE (bit 5)
    li t0, (1 << 5)
    csrrc zero, sstatus, t0

    # Clear SIE (bit 1)
    li t0, (1 << 1)
    csrrc zero, sstatus, t0

    # Set SPP = S-mode (bit 8) so we stay in S-mode after SRET
    li t0, (1 << 8)
    csrrs zero, sstatus, t0

    # Read sstatus BEFORE SRET - should have SPIE=0, SIE=0
    csrr t0, sstatus
    # Write to memory for inspection (address 0x2000)
    li t1, 0x2000
    sw t0, 0(t1)

    # Set return address
    la t0, after_sret
    csrw sepc, t0

    # Execute SRET
    sret

after_sret:
    # Read sstatus AFTER SRET - should have SPIE=1 per spec
    csrr t0, sstatus
    # Write to memory for inspection (address 0x2004)
    li t1, 0x2004
    sw t0, 0(t1)

    # Check if SPIE is set (bit 5)
    li t1, (1 << 5)
    and t2, t0, t1
    beqz t2, test_fail    # If SPIE=0, fail

    # Success!
    li x28, 0x600DF00D    # TEST_PASS marker
    ebreak

test_fail:
    li x28, 0xdeaddead    # TEST_FAIL marker
    ebreak
