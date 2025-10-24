# Check privilege mode when in S-mode
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE

    # Read MPP before entering S-mode
    csrr a0, mstatus
    srli a0, a0, 11
    andi a0, a0, 3          # Extract MPP bits [12:11]

    # Delegate to S-mode
    li t0, 0xFFFF
    csrw medeleg, t0
    csrw mideleg, t0

    # Prepare to enter S-mode (MPP should be set to 01)
    la t0, smode_code
    csrw mepc, t0
    li t1, ~0x1800          # Clear MPP bits
    csrr t2, mstatus
    and t2, t2, t1
    li t1, (1 << 11)        # Set MPP = 01 (S-mode)
    or t2, t2, t1
    csrw mstatus, t2
    
    # Save MPP value before MRET
    csrr a1, mstatus
    srli a1, a1, 11
    andi a1, a1, 3          # Extract MPP bits [12:11]

    # Enter S-mode via MRET
    mret

smode_code:
    # Now in S-mode
    # Try to read mstatus (should work from S-mode)
    csrr a2, mstatus
    
    # Try to read sstatus (should work from S-mode)
    csrr a3, sstatus

    # If we got here without trap, test passed
    TEST_PASS

test_fail:
    TEST_FAIL

m_trap_handler:
    # Save the cause
    csrr a4, mcause
    TEST_FAIL

s_trap_handler:
    # Save the cause
    csrr a5, scause
    TEST_FAIL

TRAP_TEST_DATA_AREA
