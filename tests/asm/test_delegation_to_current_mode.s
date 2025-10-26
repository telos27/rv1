# ==============================================================================
# Test: Delegation to Current Mode
# ==============================================================================
#
# Purpose: Verify behavior when exception delegates to the current privilege mode
#
# Test Flow:
#   1. Configure medeleg to delegate illegal instruction to S-mode
#   2. Enter S-mode
#   3. Execute illegal instruction while in S-mode
#   4. Verify trap goes to S-mode handler (not M-mode)
#   5. Verify SEPC, SCAUSE, and SPP are set correctly
#   6. Verify SPP preserves current privilege (S-mode)
#
# Expected Result:
#   - Delegated exception to S-mode while in S-mode still traps to S-mode
#   - State saved correctly (SPP = S)
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
    # TEST: Illegal instruction in S-mode with delegation to S-mode
    ###########################################################################
    # Stage 1: Setup delegation
    li s0, 1

    # Delegate illegal instruction (cause 2) to S-mode
    li t0, (1 << CAUSE_ILLEGAL_INSTR)
    csrw medeleg, t0

    # Set S-mode trap vector
    la t0, s_trap_handler
    csrw stvec, t0

    # Stage 2: Enter S-mode
    li s0, 2
    ENTER_SMODE_M smode_code

smode_code:
    # Stage 3: Now in S-mode, trigger illegal instruction
    li s0, 3

    # Execute an illegal instruction (try to access M-mode CSR)
    # This should trap to S-mode handler (not M-mode) because medeleg[2]=1
    csrr t0, mtvec          # Illegal in S-mode!

    # Should never reach here
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
s_trap_handler:
    # Stage 4: Trapped to S-mode handler
    li s0, 4

    # Verify we're handling an illegal instruction
    csrr t0, scause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # Verify SEPC points to the illegal instruction
    csrr t0, sepc
    la t1, smode_code
    addi t1, t1, 4          # Offset past li s0,3 (4 bytes)
    bne t0, t1, test_fail

    # Verify SPP is set to S-mode (1)
    csrr t0, sstatus
    li t1, MSTATUS_SPP
    and t2, t0, t1
    beqz t2, test_fail      # SPP should be set (indicating S-mode)

    # SUCCESS - we successfully verified:
    # 1. Exception delegated to S-mode while in S-mode
    # 2. Trap went to S-mode handler (not M-mode)
    # 3. SPP preserved current privilege correctly
    TEST_PASS

m_trap_handler:
    # Should NOT reach here - delegation should send to S-mode
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
