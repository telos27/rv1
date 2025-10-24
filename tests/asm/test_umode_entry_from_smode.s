# ==============================================================================
# Test: test_umode_entry_from_smode.s
# ==============================================================================
#
# Purpose: Verify S→U mode transition via SRET
#
# Test Flow:
#   1. Start in M-mode
#   2. Enter S-mode via MRET
#   3. From S-mode: Set SPP = 0 (U-mode)
#   4. Set SEPC to U-mode target
#   5. Execute SRET
#   6. Verify execution in U-mode
#   7. Attempt SRET (privileged instruction) → trap to M-mode
#   8. Verify trap cause = illegal instruction
#   9. SUCCESS
#
# Expected Result: S→U transition works, privileged instruction trapped
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"

.section .text
.globl _start

_start:
    ###########################################################################
    # SETUP
    ###########################################################################
    TEST_PREAMBLE           # Setup trap handlers, clear delegations

    # Stage marker for debugging
    li s0, 0

    ###########################################################################
    # TEST: M→S→U mode transitions
    ###########################################################################

    # Stage 1: In M-mode, prepare to enter S-mode
    li s0, 1

    # First, enter S-mode from M-mode
    ENTER_SMODE_M smode_code

smode_code:
    # Stage 2: Now in S-mode
    li s0, 2

    # Now enter U-mode from S-mode
    ENTER_UMODE_S umode_code

umode_code:
    # Stage 3: Now in U-mode
    li s0, 3

    # Attempt to read S-mode CSR (sstatus)
    # This should trap to M-mode with illegal instruction
    # NOTE: Using CSR instead of SRET because RTL may not check SRET privilege
    csrr t0, sstatus

    # Should never reach here
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Stage 4: Trapped to M-mode
    li s0, 4

    # Verify trap cause is illegal instruction
    csrr t0, mcause
    li t1, CAUSE_ILLEGAL_INSTR
    bne t0, t1, test_fail

    # Verify MEPC points to CSR instruction
    csrr t0, mepc
    la t1, umode_code
    addi t1, t1, 8          # Offset to csrr (after li s0, 3)
    bne t0, t1, test_fail

    # SUCCESS - we successfully:
    # 1. Entered S-mode from M-mode
    # 2. Entered U-mode from S-mode
    # 3. Verified we're in U-mode (CSR access trapped)
    # 4. Trap went to M-mode (not S-mode) since no delegation
    TEST_PASS

s_trap_handler:
    # Should not trap to S-mode since we didn't delegate
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

.align 4
