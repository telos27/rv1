# Test 1: Basic Privilege Mode Testing
# Very simple test to verify privilege infrastructure exists
# Tests:
# - Initial privilege mode (should be M-mode = 11)
# - Basic CSR access

.section .text
.globl _start

_start:
    # Test 1: We start in M-mode
    # Try to access M-mode only CSR (mscratch)
    li      t0, 0xDEADBEEF
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, fail

    # Test 2: Read mstatus
    csrr    t2, mstatus

    # Test 3: Write and read medeleg (trap delegation register)
    li      t0, 0x00000555
    csrw    medeleg, t0
    csrr    t1, medeleg
    bne     t0, t1, fail

    # SUCCESS
    j       pass

pass:
    li      t1, 0xDEADBEEF       # Success marker
    li      t2, 1                # Test passed
    mv      x28, t1              # x28 is checked by testbench
    ebreak

fail:
    li      t1, 0xDEADDEAD       # Failure marker
    li      t2, 0                # Test failed
    mv      x28, t1              # x28 is checked by testbench
    ebreak

.align 4
