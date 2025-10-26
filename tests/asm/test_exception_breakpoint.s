# ==============================================================================
# Test: test_exception_breakpoint.s
# ==============================================================================
#
# Purpose: Verify EBREAK instruction (exception cause code 3)
#
# Test Flow:
#   Stage 1: EBREAK from M-mode
#   Stage 2: EBREAK from S-mode (delegated to M-mode)
#   Stage 3: EBREAK from S-mode (delegated to S-mode)
#   Stage 4: EBREAK from U-mode (delegated to M-mode)
#   Stage 5: EBREAK from U-mode (delegated to S-mode)
#
# Expected Results:
#   - mcause = 3 (EBREAK)
#   - mepc/sepc points to EBREAK instruction
#   - mtval/stval should be 0 (no additional info)
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

    li s0, 0                # Stage counter

    ###########################################################################
    # STAGE 1: EBREAK from M-mode
    ###########################################################################
stage1:
    li s0, 1
    CLEAR_EXCEPTION_DELEGATION

    la t0, stage1_ebreak
    csrw mepc, t0           # Save address for verification

stage1_ebreak:
    ebreak                  # Should trap to M-mode

    # Execution continues here after MRET from handler
    li s0, 2

    ###########################################################################
    # STAGE 2: EBREAK from S-mode (not delegated)
    ###########################################################################
stage2:
    li s0, 2
    CLEAR_EXCEPTION_DELEGATION
    ENTER_SMODE_M smode_code2

smode_code2:
    li s0, 22
    ebreak                  # Should trap to M-mode

    # Should not reach here (EBREAK doesn't auto-advance)
    TEST_FAIL

    ###########################################################################
    # STAGE 3: EBREAK from S-mode (delegated to S-mode)
    ###########################################################################
stage3:
    li s0, 3
    DELEGATE_EXCEPTION CAUSE_BREAKPOINT
    ENTER_SMODE_M smode_code3

smode_code3:
    li s0, 33
    ebreak                  # Should trap to S-mode handler

    # Should not reach here
    TEST_FAIL

    ###########################################################################
    # STAGE 4: EBREAK from U-mode (not delegated)
    ###########################################################################
stage4:
    li s0, 4
    CLEAR_EXCEPTION_DELEGATION
    ENTER_UMODE_M umode_code4

umode_code4:
    li s0, 44
    ebreak                  # Should trap to M-mode

    # Should not reach here
    TEST_FAIL

    ###########################################################################
    # STAGE 5: EBREAK from U-mode (delegated to S-mode)
    ###########################################################################
stage5:
    li s0, 5
    DELEGATE_EXCEPTION CAUSE_BREAKPOINT
    ENTER_SMODE_M smode_setup5

smode_setup5:
    # From S-mode, enter U-mode
    ENTER_UMODE_S umode_code5

umode_code5:
    li s0, 55
    ebreak                  # Should trap to S-mode (delegated)

    # Should not reach here
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # First check if this is ECALL from S-mode (stage transition)
    csrr t0, mcause
    li t1, CAUSE_ECALL_S
    beq t0, t1, ecall_from_s_handler

    # Determine which stage we're in
    li t6, 1
    beq s0, t6, m_handle_stage1
    li t6, 22
    beq s0, t6, m_handle_stage2
    li t6, 44
    beq s0, t6, m_handle_stage4

    # Unexpected trap to M-mode
    TEST_FAIL

m_handle_stage1:
    # Verify cause = BREAKPOINT
    csrr t0, mcause
    li t1, CAUSE_BREAKPOINT
    bne t0, t1, test_fail

    # Verify MEPC points to EBREAK
    csrr t0, mepc
    la t1, stage1_ebreak
    bne t0, t1, test_fail

    # Verify mtval = 0 (EBREAK provides no additional info)
    csrr t0, mtval
    bnez t0, test_fail

    # Advance mepc past EBREAK (4 bytes for uncompressed, 2 for compressed)
    # Check if instruction is compressed
    csrr t0, mepc
    lhu t1, 0(t0)           # Load halfword
    andi t2, t1, 0x3
    li t3, 0x3
    beq t2, t3, 1f          # If bits[1:0] == 11, it's uncompressed (4 bytes)
    addi t0, t0, 2          # Compressed EBREAK (c.ebreak = 0x9002)
    j 2f
1:
    addi t0, t0, 4          # Uncompressed EBREAK
2:
    csrw mepc, t0
    mret

m_handle_stage2:
    # EBREAK from S-mode, not delegated
    csrr t0, mcause
    li t1, CAUSE_BREAKPOINT
    bne t0, t1, test_fail

    # Verify mtval = 0
    csrr t0, mtval
    bnez t0, test_fail

    # Return to stage 3
    la t0, stage3
    csrw mepc, t0
    SET_MPP PRIV_M
    mret

m_handle_stage4:
    # EBREAK from U-mode, not delegated
    csrr t0, mcause
    li t1, CAUSE_BREAKPOINT
    bne t0, t1, test_fail

    # Verify mtval = 0
    csrr t0, mtval
    bnez t0, test_fail

    # Return to stage 5
    la t0, stage5
    csrw mepc, t0
    SET_MPP PRIV_M
    mret

s_trap_handler:
    # Determine which stage we're in
    li t6, 33
    beq s0, t6, s_handle_stage3
    li t6, 55
    beq s0, t6, s_handle_stage5

    # Unexpected trap to S-mode
    TEST_FAIL

s_handle_stage3:
    # EBREAK from S-mode, delegated to S-mode
    csrr t0, scause
    li t1, CAUSE_BREAKPOINT
    bne t0, t1, test_fail

    # Verify stval = 0
    csrr t0, stval
    bnez t0, test_fail

    # Return to stage 4 (via M-mode)
    # From S-mode, we need to ECALL to M-mode to change privilege
    la s1, stage4
    ecall

s_handle_stage5:
    # EBREAK from U-mode, delegated to S-mode
    csrr t0, scause
    li t1, CAUSE_BREAKPOINT
    bne t0, t1, test_fail

    # Verify stval = 0
    csrr t0, stval
    bnez t0, test_fail

    # SUCCESS - All stages passed
    TEST_PASS

# =============================================================================
# ECALL from S-mode handler (for stage transitions)
# =============================================================================
ecall_from_s_handler:
    # Return to address in s1
    csrw mepc, s1
    SET_MPP PRIV_M
    mret

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
