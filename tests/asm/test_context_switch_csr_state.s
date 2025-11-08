# ==============================================================================
# Test: CSR Context Switch - Control/Status Register Preservation
# ==============================================================================
#
# This test verifies that CSRs are correctly preserved across context switches.
# This is critical for OS task switching where each task has its own CSR state.
#
# CSRs tested (Supervisor-mode context):
# - SEPC (Supervisor Exception Program Counter)
# - SSTATUS (Supervisor Status Register)
# - SSCRATCH (Supervisor Scratch Register)
# - SCAUSE (Supervisor Cause Register)
# - STVAL (Supervisor Trap Value Register)
#
# Test Sequence:
# 1. Setup "Task A" CSR state with distinct values
# 2. Save Task A CSR context to memory
# 3. Setup "Task B" CSR state with different values
# 4. Save Task B CSR context to memory
# 5. Restore Task A CSR context from memory
# 6. Verify all Task A CSRs are correctly restored
# 7. Restore Task B CSR context from memory
# 8. Verify all Task B CSRs are correctly restored
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    TEST_STAGE 1

    ###########################################################################
    # Setup Task A CSR state - Load distinctive values
    ###########################################################################

    # Setup Task A CSR values (distinctive patterns)
    li      t0, 0x80001000       # SEPC value for Task A
    csrw    sepc, t0

    li      t0, 0x00000122       # SSTATUS value (SPP=1, SPIE=1, SIE=0)
    csrw    sstatus, t0

    li      t0, 0xAAAAAAAA       # SSCRATCH value
    csrw    sscratch, t0

    li      t0, 0x00000008       # SCAUSE value (ECALL from U-mode)
    csrw    scause, t0

    li      t0, 0x12345678       # STVAL value
    csrw    stval, t0

    TEST_STAGE 2

    ###########################################################################
    # Save Task A CSR context to memory
    ###########################################################################

    la      t1, task_a_csr_context

    csrr    t0, sepc
    sw      t0, 0(t1)            # Save SEPC

    csrr    t0, sstatus
    sw      t0, 4(t1)            # Save SSTATUS

    csrr    t0, sscratch
    sw      t0, 8(t1)            # Save SSCRATCH

    csrr    t0, scause
    sw      t0, 12(t1)           # Save SCAUSE

    csrr    t0, stval
    sw      t0, 16(t1)           # Save STVAL

    TEST_STAGE 3

    ###########################################################################
    # Setup Task B CSR state - Different values
    ###########################################################################

    li      t0, 0x80002000       # SEPC value for Task B
    csrw    sepc, t0

    li      t0, 0x00000020       # SSTATUS value (SPP=0, SPIE=1, SIE=0)
    csrw    sstatus, t0

    li      t0, 0x55555555       # SSCRATCH value
    csrw    sscratch, t0

    li      t0, 0x0000000D       # SCAUSE value (Load page fault)
    csrw    scause, t0

    li      t0, 0x9ABCDEF0       # STVAL value
    csrw    stval, t0

    TEST_STAGE 4

    ###########################################################################
    # Save Task B CSR context to memory
    ###########################################################################

    la      t1, task_b_csr_context

    csrr    t0, sepc
    sw      t0, 0(t1)

    csrr    t0, sstatus
    sw      t0, 4(t1)

    csrr    t0, sscratch
    sw      t0, 8(t1)

    csrr    t0, scause
    sw      t0, 12(t1)

    csrr    t0, stval
    sw      t0, 16(t1)

    TEST_STAGE 5

    ###########################################################################
    # Restore Task A CSR context and verify
    ###########################################################################

    la      t1, task_a_csr_context

    lw      t0, 0(t1)
    csrw    sepc, t0

    lw      t0, 4(t1)
    csrw    sstatus, t0

    lw      t0, 8(t1)
    csrw    sscratch, t0

    lw      t0, 12(t1)
    csrw    scause, t0

    lw      t0, 16(t1)
    csrw    stval, t0

    TEST_STAGE 6

    ###########################################################################
    # Verify Task A CSR values are correct
    ###########################################################################

    # Verify SEPC
    csrr    t0, sepc
    li      t1, 0x80001000
    bne     t0, t1, test_fail

    # Verify SSTATUS
    csrr    t0, sstatus
    li      t1, 0x00000122
    bne     t0, t1, test_fail

    # Verify SSCRATCH
    csrr    t0, sscratch
    li      t1, 0xAAAAAAAA
    bne     t0, t1, test_fail

    # Verify SCAUSE
    csrr    t0, scause
    li      t1, 0x00000008
    bne     t0, t1, test_fail

    # Verify STVAL
    csrr    t0, stval
    li      t1, 0x12345678
    bne     t0, t1, test_fail

    TEST_STAGE 7

    ###########################################################################
    # Restore Task B CSR context and verify
    ###########################################################################

    la      t1, task_b_csr_context

    lw      t0, 0(t1)
    csrw    sepc, t0

    lw      t0, 4(t1)
    csrw    sstatus, t0

    lw      t0, 8(t1)
    csrw    sscratch, t0

    lw      t0, 12(t1)
    csrw    scause, t0

    lw      t0, 16(t1)
    csrw    stval, t0

    TEST_STAGE 8

    ###########################################################################
    # Verify Task B CSR values are correct
    ###########################################################################

    # Verify SEPC
    csrr    t0, sepc
    li      t1, 0x80002000
    bne     t0, t1, test_fail

    # Verify SSTATUS
    csrr    t0, sstatus
    li      t1, 0x00000020
    bne     t0, t1, test_fail

    # Verify SSCRATCH
    csrr    t0, sscratch
    li      t1, 0x55555555
    bne     t0, t1, test_fail

    # Verify SCAUSE
    csrr    t0, scause
    li      t1, 0x0000000D
    bne     t0, t1, test_fail

    # Verify STVAL
    csrr    t0, stval
    li      t1, 0x9ABCDEF0
    bne     t0, t1, test_fail

    TEST_STAGE 9

    ###########################################################################
    # Additional test: Round-robin context switching
    ###########################################################################

    # This simulates multiple rapid context switches between tasks
    # Switch back to Task A
    la      t1, task_a_csr_context
    lw      t0, 0(t1)
    csrw    sepc, t0
    lw      t0, 8(t1)
    csrw    sscratch, t0

    # Verify Task A SEPC and SSCRATCH
    csrr    t0, sepc
    li      t1, 0x80001000
    bne     t0, t1, test_fail
    csrr    t0, sscratch
    li      t1, 0xAAAAAAAA
    bne     t0, t1, test_fail

    # Switch to Task B
    la      t1, task_b_csr_context
    lw      t0, 0(t1)
    csrw    sepc, t0
    lw      t0, 8(t1)
    csrw    sscratch, t0

    # Verify Task B SEPC and SSCRATCH
    csrr    t0, sepc
    li      t1, 0x80002000
    bne     t0, t1, test_fail
    csrr    t0, sscratch
    li      t1, 0x55555555
    bne     t0, t1, test_fail

    # Switch back to Task A again
    la      t1, task_a_csr_context
    lw      t0, 0(t1)
    csrw    sepc, t0
    lw      t0, 8(t1)
    csrw    sscratch, t0

    # Final verification of Task A
    csrr    t0, sepc
    li      t1, 0x80001000
    bne     t0, t1, test_fail
    csrr    t0, sscratch
    li      t1, 0xAAAAAAAA
    bne     t0, t1, test_fail

    # All tests passed!
    j       test_pass

###############################################################################
# Trap handlers (minimal - not expected to be called)
###############################################################################

m_trap_handler:
    TEST_STAGE 0xFF
    j       test_fail

s_trap_handler:
    TEST_STAGE 0xFE
    j       test_fail

###############################################################################
# Test result handlers
###############################################################################

test_pass:
    li gp, 1
    j end_test

test_fail:
    li gp, 0
    j end_test

end_test:
    li t0, 0x80002100
    sw gp, 0(t0)
1:  j 1b

###############################################################################
# Data section
###############################################################################

.section .data

.align 4
task_a_csr_context:
    .space 20               # 5 CSRs × 4 bytes (SEPC, SSTATUS, SSCRATCH, SCAUSE, STVAL)

.align 4
task_b_csr_context:
    .space 20               # 5 CSRs × 4 bytes (SEPC, SSTATUS, SSCRATCH, SCAUSE, STVAL)
