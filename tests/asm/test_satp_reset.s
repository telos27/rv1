# ==============================================================================
# Test: SATP Reset Value Check
# ==============================================================================
#
# This minimal test verifies that SATP is 0 at reset (bare mode).
# If this fails, it indicates a CSR initialization problem.
#
# ==============================================================================

.section .text
.globl _start

_start:
    # Read SATP immediately after reset
    csrr    t0, satp

    # Check if SATP is zero
    bnez    t0, test_fail

test_pass:
    # Test passed
    li      t0, 0xDEADBEEF
    mv      x28, t0
    ebreak

test_fail:
    # Test failed - SATP was not zero!
    # Save SATP value in t1 for debugging
    mv      t1, t0
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

.section .data
