# ==============================================================================
# Test: test_xret_privilege_trap.s
# ==============================================================================
#
# Purpose: Verify MRET and SRET trap when executed in insufficient privilege
#
# Test Flow:
#   1. Test SRET in U-mode (should trap with cause=2, illegal instruction)
#   2. Test MRET in U-mode (should trap with cause=2, illegal instruction)
#   3. Test MRET in S-mode (should trap with cause=2, illegal instruction)
#   4. SUCCESS
#
# Expected Results:
#   - SRET in U-mode → illegal instruction trap
#   - MRET in U-mode → illegal instruction trap
#   - MRET in S-mode → illegal instruction trap
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    li s0, 0

    ###########################################################################
    # TEST 1: SRET in U-mode should trap
    ###########################################################################

    li s0, 1
    ENTER_UMODE_M test1_umode

test1_umode:
    li s0, 2
    sret                     # Should trap with illegal instruction
    TEST_FAIL                # Should not reach here

    ###########################################################################
    # TEST 2: MRET in U-mode should trap
    ###########################################################################

test2_start:
    li s0, 3
    ENTER_UMODE_M test2_umode

test2_umode:
    li s0, 4
    mret                     # Should trap with illegal instruction
    TEST_FAIL                # Should not reach here

    ###########################################################################
    # TEST 3: MRET in S-mode should trap
    ###########################################################################

test3_start:
    li s0, 5

    # Enter S-mode via MRET
    # Set mepc to test3_smode
    la t0, test3_smode
    csrw mepc, t0

    # Set MPP to S-mode (01)
    li t0, (1 << 11)         # MPP = S-mode
    csrs mstatus, t0

    li s0, 6
    mret                     # Jump to S-mode

test3_smode:
    li s0, 7
    mret                     # Should trap with illegal instruction from S-mode
    TEST_FAIL                # Should not reach here

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Get trap cause
    csrr t0, mcause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # Check which test we're in based on s0
    li t1, 2
    beq s0, t1, test1_success

    li t1, 4
    beq s0, t1, test2_success

    li t1, 7
    beq s0, t1, test3_success

    # Unexpected trap
    j test_fail

test1_success:
    # Test 1 passed, continue to test 2
    # Advance mepc past the illegal SRET instruction (4 bytes)
    csrr t0, mepc
    addi t0, t0, 4
    csrw mepc, t0
    # Jump directly to test2_start on return
    la t0, test2_start
    csrw mepc, t0
    mret

test2_success:
    # Test 2 passed, continue to test 3
    # Jump directly to test3_start on return
    la t0, test3_start
    csrw mepc, t0
    mret

test3_success:
    # All tests passed!
    TEST_PASS

s_trap_handler:
    # S-mode trap handler - MRET in S-mode should have been delegated to M-mode
    # If we get here, something is wrong
    TEST_FAIL

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
