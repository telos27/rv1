# ==============================================================================
# Test: Delegation Disable
# ==============================================================================
#
# Purpose: Verify that clearing delegation works correctly
#
# Test Flow:
#   1. Delegate illegal instruction exception to S-mode via medeleg
#   2. Enter S-mode and trigger illegal instruction → trap to S-mode
#   3. Clear delegation (medeleg[2] = 0)
#   4. Enter S-mode again and trigger same exception → trap to M-mode
#   5. Verify correct handler invoked in each case
#
# Expected Result:
#   - With delegation: exception goes to S-mode handler
#   - Without delegation: exception goes to M-mode handler
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

    # Stage marker for debugging
    li s0, 0

    ###########################################################################
    # TEST 1: With delegation enabled
    ###########################################################################
    # Stage 1: Enable delegation
    li s0, 1

    # Delegate illegal instruction (cause 2) to S-mode
    li t0, (1 << CAUSE_ILLEGAL_INSTR)
    csrw medeleg, t0

    # Trap handlers are already set by TEST_PREAMBLE
    # m_trap_handler and s_trap_handler will handle routing

    # Stage 2: Enter S-mode
    li s0, 2
    ENTER_SMODE_M smode_test1

smode_test1:
    # Stage 3: Trigger illegal instruction in S-mode
    li s0, 3

    # This should trap to S-mode handler (delegation is active)
    csrr t0, mtvec          # Illegal in S-mode

    # Should never reach here
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
# M-mode trap handler (required by TEST_PREAMBLE)
m_trap_handler:
    # Check which stage we're in
    li t2, 5
    beq s0, t2, m_handler_stage5

    # Stage 8: After test 2, illegal instruction without delegation
    li t2, 7
    bgt s0, t2, m_handler_stage8

    # If we're here in stage 1-3, delegation failed
    TEST_FAIL

m_handler_stage5:
    # Back in M-mode from ecall in s_trap_handler
    # Verify this is an ecall from S-mode
    csrr t0, mcause
    li t1, CAUSE_ECALL_S
    bne t0, t1, test_fail

    # Stage 6: Prepare for test 2 (delegation disabled)
    li s0, 6

    # Clear delegation for test 2 (must be done from M-mode)
    csrw medeleg, zero

    # Enter S-mode again
    ENTER_SMODE_M smode_test2

m_handler_stage8:
    # Stage 8: Trapped to M-mode (no delegation)
    li s0, 8

    # Verify cause is illegal instruction
    csrr t0, mcause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # SUCCESS!
    TEST_PASS

# S-mode trap handler (required by TEST_PREAMBLE)
s_trap_handler:
    # Should only be called in test 1 (stages 1-4)
    li t2, 4
    bgt s0, t2, test_fail  # If stage > 4, delegation should be off

    # Stage 4: Successfully trapped to S-mode (delegation worked)
    li s0, 4

    # Verify cause
    csrr t0, scause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # Stage 5: Return to M-mode via ecall (cannot clear medeleg from S-mode)
    li s0, 5
    ecall                   # This will go to M-mode

smode_test2:
    # Stage 7: Trigger illegal instruction again
    li s0, 7

    # This should trap to M-mode handler (delegation is disabled)
    csrr t0, mie            # Illegal in S-mode

    # Should never reach here
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
