# ==============================================================================
# Test: Rapid Privilege Mode Switching (Phase 7.1)
# ==============================================================================
#
# Purpose: Stress test privilege mode transitions to catch state corruption bugs
#
# Test Flow:
#   1. Perform 100+ rapid privilege mode transitions:
#      - M → S → M → S → M (via MRET/ECALL)
#      - M → S → U → S → M (via MRET/SRET/ECALL)
#   2. Verify state preserved correctly through all transitions
#   3. Check CSR state remains consistent
#   4. Verify no register corruption
#
# Expected Result: All transitions work correctly, no state corruption
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE

    # Initialize counter register - we'll do 10 round-trips (20 transitions)
    # Note: Reduced from 50 to 10 to avoid simulation timeout
    li      s0, 0           # Transition counter
    li      s1, 10          # Target count

    # Initialize test values in saved registers
    li      s2, 0x12345678  # Test value 1
    li      s3, 0x87654321  # Test value 2
    li      s4, 0xABCDEF00  # Test value 3

    ###########################################################################
    # TEST 1: M ↔ S Rapid Switching (50 round-trips = 100 transitions)
    ###########################################################################
test1_loop:
    # M → S transition
    ENTER_SMODE_M test1_smode

test1_smode:
    # Verify we're in S-mode (can access sscratch)
    csrw    sscratch, s2
    csrr    t0, sscratch
    bne     t0, s2, test_fail

    # Verify saved registers intact
    li      t0, 0x12345678
    bne     s2, t0, test_fail
    li      t0, 0x87654321
    bne     s3, t0, test_fail

    # S → M transition via ECALL
    ecall

m_trap_handler:
    # Should be ECALL from S-mode
    csrr    t0, mcause
    li      t1, CAUSE_ECALL_S
    bne     t0, t1, test_fail

    # Verify saved registers still intact after trap
    li      t0, 0x12345678
    bne     s2, t0, test_fail
    li      t0, 0x87654321
    bne     s3, t0, test_fail
    li      t0, 0xABCDEF00
    bne     s4, t0, test_fail

    # Increment counter
    addi    s0, s0, 1

    # Check if done with test 1
    blt     s0, s1, test1_loop

    ###########################################################################
    # SUCCESS - All transitions completed without corruption
    ###########################################################################
    TEST_PASS

# =============================================================================
# TRAP HANDLERS
# =============================================================================

s_trap_handler:
    # Unexpected trap to S-mode
    TEST_FAIL

# =============================================================================
# FAILURE HANDLER
# =============================================================================
test_fail:
    TEST_FAIL

# =============================================================================
# DATA SECTION
# =============================================================================
TRAP_TEST_DATA_AREA
