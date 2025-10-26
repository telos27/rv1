# ==============================================================================
# Test: test_exception_instr_misaligned.s
# ==============================================================================
#
# Purpose: Verify instruction address misaligned exception (cause code 0)
#
# Test Flow:
#   Stage 1: MRET to odd address (misaligned)
#   Stage 2: MRET to odd address (different offset)
#   Stage 3: SRET to odd address (from S-mode)
#
# Expected Results:
#   - mcause/scause = 0 (Instruction address misaligned)
#   - mepc/sepc points to MRET/SRET instruction
#   - mtval/stval contains the misaligned target address (odd)
#
# Note: With C extension enabled, 2-byte aligned addresses are valid.
#       We need to test 1-byte misalignment (odd addresses) which are always invalid.
#       JALR cannot create misaligned jumps (spec says it clears bit 0).
#       Therefore we use MRET/SRET which load PC from mepc/sepc without clearing bit 0.
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
    # STAGE 1: MRET to odd address (misaligned)
    ###########################################################################
stage1:
    li s0, 1
    CLEAR_EXCEPTION_DELEGATION

    # Set mepc to odd address (misaligned)
    la t0, misaligned_target1
    ori t0, t0, 1           # Force odd address
    csrw mepc, t0

    # Set MPP to M-mode so we stay in M-mode after MRET
    SET_MPP PRIV_M

    # Save address of MRET for verification
    la s1, mret_instr1

    li s2, 0                # Clear flag (should not be set if misalignment detected)

mret_instr1:
    mret                    # This should attempt to jump to odd address and trap

    # Should not reach here
    TEST_FAIL

misaligned_target1:
    .align 2
    li s2, 1                # This should not execute
    TEST_FAIL

    ###########################################################################
    # STAGE 2: MRET to odd address with different offset
    ###########################################################################
stage2:
    .align 2
    li s0, 2

    # Set mepc to odd address
    la t0, misaligned_target2
    ori t0, t0, 1           # Force odd address
    csrw mepc, t0

    SET_MPP PRIV_M
    la s1, mret_instr2
    li s2, 0

mret_instr2:
    mret                    # Should trap on misaligned fetch

    # Should not reach here
    TEST_FAIL

misaligned_target2:
    .align 2
    li s2, 2
    TEST_FAIL

    ###########################################################################
    # STAGE 3: SRET to odd address (from S-mode, delegated)
    ###########################################################################
stage3:
    .align 2
    li s0, 3

    # Delegate misaligned fetch to S-mode
    DELEGATE_EXCEPTION CAUSE_MISALIGNED_FETCH

    # Enter S-mode first
    ENTER_SMODE_M smode_code3

smode_code3:
    # In S-mode, set sepc to odd address
    la t0, misaligned_target3
    ori t0, t0, 1           # Force odd address
    csrw sepc, t0

    # Set SPP to S-mode
    csrr t0, sstatus
    ori t0, t0, 0x100       # Set SPP bit (bit 8)
    csrw sstatus, t0

    la s1, sret_instr3
    li s2, 0

sret_instr3:
    sret                    # Should trap on misaligned fetch

    # Should not reach here
    TEST_FAIL

misaligned_target3:
    .align 2
    li s2, 3
    TEST_FAIL

# =============================================================================
# TRAP HANDLERS
# =============================================================================
m_trap_handler:
    # Check if this is an ECALL from S-mode (for stage 3 entry)
    csrr t0, mcause
    li t1, CAUSE_ECALL_S
    beq t0, t1, handle_ecall_s

    # Verify cause = Instruction address misaligned
    li t1, CAUSE_MISALIGNED_FETCH
    bne t0, t1, test_fail

    # Verify mepc points to the MRET instruction
    csrr t0, mepc
    bne t0, s1, test_fail

    # Verify mtval contains the misaligned target address (odd address)
    csrr t0, mtval
    andi t1, t0, 1          # Check if bit 0 is set (odd address)
    beqz t1, test_fail      # Should be odd

    # Verify s2 was not modified (target never reached)
    bnez s2, test_fail

    # Determine which stage we're in and continue
    li t0, 1
    beq s0, t0, handle_stage1
    li t0, 2
    beq s0, t0, handle_stage2
    li t0, 3
    beq s0, t0, handle_stage3_from_smode

    # Unexpected stage
    TEST_FAIL

handle_ecall_s:
    # Stage 3 setup - enter S-mode
    la t0, smode_code3
    csrw mepc, t0
    SET_MPP PRIV_S
    mret

handle_stage1:
    # Return to stage2
    la t0, stage2
    csrw mepc, t0
    mret

handle_stage2:
    # Return to stage3
    la t0, stage3
    csrw mepc, t0
    mret

handle_stage3_from_smode:
    # Stage 3 trapped from S-mode SRET, return to M-mode success
    la t0, test_pass_label
    csrw mepc, t0
    mret

test_pass_label:
    TEST_PASS

s_trap_handler:
    # Stage 3: SRET to misaligned address should trap to S-mode
    li t0, 3
    bne s0, t0, test_fail

    # Verify cause = Instruction address misaligned
    csrr t0, scause
    li t1, CAUSE_MISALIGNED_FETCH
    bne t0, t1, test_fail

    # Verify sepc points to SRET instruction
    csrr t0, sepc
    bne t0, s1, test_fail

    # Verify stval contains misaligned address
    csrr t0, stval
    andi t1, t0, 1
    beqz t1, test_fail

    # Verify s2 not modified
    bnez s2, test_fail

    # Return to M-mode to complete test
    ecall

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
