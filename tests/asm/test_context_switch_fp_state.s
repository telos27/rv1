# ==============================================================================
# Test: FP Context Switch - Floating-Point Register Preservation
# ==============================================================================
#
# This test verifies that floating-point registers (FPRs) and FCSR are correctly
# preserved across context switches. This is essential for multitasking with FP.
#
# Test Sequence:
# 1. Setup "Task A" with distinct values in all FPRs (f0-f31) and FCSR
# 2. Save Task A FP context to memory
# 3. Setup "Task B" with different values in all FPRs and FCSR
# 4. Save Task B FP context to memory
# 5. Restore Task A FP context from memory
# 6. Verify all Task A FP registers and FCSR are correctly restored
# 7. Restore Task B FP context from memory
# 8. Verify all Task B FP registers and FCSR are correctly restored
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
    # Enable FPU (set MSTATUS.FS = 1)
    ###########################################################################

    li      t0, 0x00006000       # FS = 1 (Initial)
    csrs    mstatus, t0

    TEST_STAGE 2

    ###########################################################################
    # Setup Task A FP state - Load distinctive values into all FPRs
    ###########################################################################

    # Load Task A values (single-precision for simplicity)
    # Pattern: 1.0, 2.0, 3.0, ..., 32.0

    la      t0, task_a_fp_values
    flw     f0,  0(t0)
    flw     f1,  4(t0)
    flw     f2,  8(t0)
    flw     f3,  12(t0)
    flw     f4,  16(t0)
    flw     f5,  20(t0)
    flw     f6,  24(t0)
    flw     f7,  28(t0)
    flw     f8,  32(t0)
    flw     f9,  36(t0)
    flw     f10, 40(t0)
    flw     f11, 44(t0)
    flw     f12, 48(t0)
    flw     f13, 52(t0)
    flw     f14, 56(t0)
    flw     f15, 60(t0)
    flw     f16, 64(t0)
    flw     f17, 68(t0)
    flw     f18, 72(t0)
    flw     f19, 76(t0)
    flw     f20, 80(t0)
    flw     f21, 84(t0)
    flw     f22, 88(t0)
    flw     f23, 92(t0)
    flw     f24, 96(t0)
    flw     f25, 100(t0)
    flw     f26, 104(t0)
    flw     f27, 108(t0)
    flw     f28, 112(t0)
    flw     f29, 116(t0)
    flw     f30, 120(t0)
    flw     f31, 124(t0)

    # Set FCSR to a known value (rounding mode = RNE, no exceptions)
    li      t0, 0x000000AA       # Distinctive pattern
    csrw    fcsr, t0

    TEST_STAGE 3

    ###########################################################################
    # Save Task A FP context to memory
    ###########################################################################

    la      t0, task_a_fp_context

    # Save all FP registers
    fsw     f0,  0(t0)
    fsw     f1,  4(t0)
    fsw     f2,  8(t0)
    fsw     f3,  12(t0)
    fsw     f4,  16(t0)
    fsw     f5,  20(t0)
    fsw     f6,  24(t0)
    fsw     f7,  28(t0)
    fsw     f8,  32(t0)
    fsw     f9,  36(t0)
    fsw     f10, 40(t0)
    fsw     f11, 44(t0)
    fsw     f12, 48(t0)
    fsw     f13, 52(t0)
    fsw     f14, 56(t0)
    fsw     f15, 60(t0)
    fsw     f16, 64(t0)
    fsw     f17, 68(t0)
    fsw     f18, 72(t0)
    fsw     f19, 76(t0)
    fsw     f20, 80(t0)
    fsw     f21, 84(t0)
    fsw     f22, 88(t0)
    fsw     f23, 92(t0)
    fsw     f24, 96(t0)
    fsw     f25, 100(t0)
    fsw     f26, 104(t0)
    fsw     f27, 108(t0)
    fsw     f28, 112(t0)
    fsw     f29, 116(t0)
    fsw     f30, 120(t0)
    fsw     f31, 124(t0)

    # Save FCSR
    csrr    t1, fcsr
    sw      t1, 128(t0)

    TEST_STAGE 4

    ###########################################################################
    # Setup Task B FP state - Different values
    ###########################################################################

    # Load Task B values (pattern: 100.0, 101.0, 102.0, ..., 131.0)
    la      t0, task_b_fp_values
    flw     f0,  0(t0)
    flw     f1,  4(t0)
    flw     f2,  8(t0)
    flw     f3,  12(t0)
    flw     f4,  16(t0)
    flw     f5,  20(t0)
    flw     f6,  24(t0)
    flw     f7,  28(t0)
    flw     f8,  32(t0)
    flw     f9,  36(t0)
    flw     f10, 40(t0)
    flw     f11, 44(t0)
    flw     f12, 48(t0)
    flw     f13, 52(t0)
    flw     f14, 56(t0)
    flw     f15, 60(t0)
    flw     f16, 64(t0)
    flw     f17, 68(t0)
    flw     f18, 72(t0)
    flw     f19, 76(t0)
    flw     f20, 80(t0)
    flw     f21, 84(t0)
    flw     f22, 88(t0)
    flw     f23, 92(t0)
    flw     f24, 96(t0)
    flw     f25, 100(t0)
    flw     f26, 104(t0)
    flw     f27, 108(t0)
    flw     f28, 112(t0)
    flw     f29, 116(t0)
    flw     f30, 120(t0)
    flw     f31, 124(t0)

    # Set different FCSR value
    li      t0, 0x00000055       # Different pattern
    csrw    fcsr, t0

    TEST_STAGE 5

    ###########################################################################
    # Save Task B FP context to memory
    ###########################################################################

    la      t0, task_b_fp_context

    fsw     f0,  0(t0)
    fsw     f1,  4(t0)
    fsw     f2,  8(t0)
    fsw     f3,  12(t0)
    fsw     f4,  16(t0)
    fsw     f5,  20(t0)
    fsw     f6,  24(t0)
    fsw     f7,  28(t0)
    fsw     f8,  32(t0)
    fsw     f9,  36(t0)
    fsw     f10, 40(t0)
    fsw     f11, 44(t0)
    fsw     f12, 48(t0)
    fsw     f13, 52(t0)
    fsw     f14, 56(t0)
    fsw     f15, 60(t0)
    fsw     f16, 64(t0)
    fsw     f17, 68(t0)
    fsw     f18, 72(t0)
    fsw     f19, 76(t0)
    fsw     f20, 80(t0)
    fsw     f21, 84(t0)
    fsw     f22, 88(t0)
    fsw     f23, 92(t0)
    fsw     f24, 96(t0)
    fsw     f25, 100(t0)
    fsw     f26, 104(t0)
    fsw     f27, 108(t0)
    fsw     f28, 112(t0)
    fsw     f29, 116(t0)
    fsw     f30, 120(t0)
    fsw     f31, 124(t0)

    csrr    t1, fcsr
    sw      t1, 128(t0)

    TEST_STAGE 6

    ###########################################################################
    # Restore Task A FP context and verify
    ###########################################################################

    la      t0, task_a_fp_context

    flw     f0,  0(t0)
    flw     f1,  4(t0)
    flw     f2,  8(t0)
    flw     f3,  12(t0)
    flw     f4,  16(t0)
    flw     f5,  20(t0)
    flw     f6,  24(t0)
    flw     f7,  28(t0)
    flw     f8,  32(t0)
    flw     f9,  36(t0)
    flw     f10, 40(t0)
    flw     f11, 44(t0)
    flw     f12, 48(t0)
    flw     f13, 52(t0)
    flw     f14, 56(t0)
    flw     f15, 60(t0)
    flw     f16, 64(t0)
    flw     f17, 68(t0)
    flw     f18, 72(t0)
    flw     f19, 76(t0)
    flw     f20, 80(t0)
    flw     f21, 84(t0)
    flw     f22, 88(t0)
    flw     f23, 92(t0)
    flw     f24, 96(t0)
    flw     f25, 100(t0)
    flw     f26, 104(t0)
    flw     f27, 108(t0)
    flw     f28, 112(t0)
    flw     f29, 116(t0)
    flw     f30, 120(t0)
    flw     f31, 124(t0)

    lw      t1, 128(t0)
    csrw    fcsr, t1

    TEST_STAGE 7

    ###########################################################################
    # Verify Task A FP registers are correct
    ###########################################################################

    # Verify each FP register against expected value from task_a_fp_values
    la      t0, task_a_fp_values
    la      t1, temp_storage

    # Check f0
    fsw     f0, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 0(t0)
    bne     t2, t3, test_fail

    # Check f1
    fsw     f1, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 4(t0)
    bne     t2, t3, test_fail

    # Check f2
    fsw     f2, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 8(t0)
    bne     t2, t3, test_fail

    # Check f3
    fsw     f3, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 12(t0)
    bne     t2, t3, test_fail

    # Check f4
    fsw     f4, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 16(t0)
    bne     t2, t3, test_fail

    # Check f5
    fsw     f5, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 20(t0)
    bne     t2, t3, test_fail

    # Check f6-f31 (continuing pattern)
    fsw     f6, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 24(t0)
    bne     t2, t3, test_fail

    fsw     f7, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 28(t0)
    bne     t2, t3, test_fail

    fsw     f8, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 32(t0)
    bne     t2, t3, test_fail

    fsw     f9, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 36(t0)
    bne     t2, t3, test_fail

    fsw     f10, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 40(t0)
    bne     t2, t3, test_fail

    fsw     f11, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 44(t0)
    bne     t2, t3, test_fail

    fsw     f12, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 48(t0)
    bne     t2, t3, test_fail

    fsw     f13, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 52(t0)
    bne     t2, t3, test_fail

    fsw     f14, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 56(t0)
    bne     t2, t3, test_fail

    fsw     f15, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 60(t0)
    bne     t2, t3, test_fail

    fsw     f16, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 64(t0)
    bne     t2, t3, test_fail

    fsw     f17, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 68(t0)
    bne     t2, t3, test_fail

    fsw     f18, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 72(t0)
    bne     t2, t3, test_fail

    fsw     f19, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 76(t0)
    bne     t2, t3, test_fail

    fsw     f20, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 80(t0)
    bne     t2, t3, test_fail

    fsw     f21, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 84(t0)
    bne     t2, t3, test_fail

    fsw     f22, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 88(t0)
    bne     t2, t3, test_fail

    fsw     f23, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 92(t0)
    bne     t2, t3, test_fail

    fsw     f24, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 96(t0)
    bne     t2, t3, test_fail

    fsw     f25, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 100(t0)
    bne     t2, t3, test_fail

    fsw     f26, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 104(t0)
    bne     t2, t3, test_fail

    fsw     f27, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 108(t0)
    bne     t2, t3, test_fail

    fsw     f28, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 112(t0)
    bne     t2, t3, test_fail

    fsw     f29, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 116(t0)
    bne     t2, t3, test_fail

    fsw     f30, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 120(t0)
    bne     t2, t3, test_fail

    fsw     f31, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 124(t0)
    bne     t2, t3, test_fail

    # Verify FCSR
    csrr    t2, fcsr
    li      t3, 0x000000AA
    bne     t2, t3, test_fail

    TEST_STAGE 8

    ###########################################################################
    # Restore Task B FP context and verify
    ###########################################################################

    la      t0, task_b_fp_context

    flw     f0,  0(t0)
    flw     f1,  4(t0)
    flw     f2,  8(t0)
    flw     f3,  12(t0)
    flw     f4,  16(t0)
    flw     f5,  20(t0)
    flw     f6,  24(t0)
    flw     f7,  28(t0)
    flw     f8,  32(t0)
    flw     f9,  36(t0)
    flw     f10, 40(t0)
    flw     f11, 44(t0)
    flw     f12, 48(t0)
    flw     f13, 52(t0)
    flw     f14, 56(t0)
    flw     f15, 60(t0)
    flw     f16, 64(t0)
    flw     f17, 68(t0)
    flw     f18, 72(t0)
    flw     f19, 76(t0)
    flw     f20, 80(t0)
    flw     f21, 84(t0)
    flw     f22, 88(t0)
    flw     f23, 92(t0)
    flw     f24, 96(t0)
    flw     f25, 100(t0)
    flw     f26, 104(t0)
    flw     f27, 108(t0)
    flw     f28, 112(t0)
    flw     f29, 116(t0)
    flw     f30, 120(t0)
    flw     f31, 124(t0)

    lw      t1, 128(t0)
    csrw    fcsr, t1

    TEST_STAGE 9

    ###########################################################################
    # Verify Task B FP registers
    ###########################################################################

    la      t0, task_b_fp_values
    la      t1, temp_storage

    # Verify all 32 FP registers (same pattern as Task A verification)
    fsw     f0, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 0(t0)
    bne     t2, t3, test_fail

    fsw     f1, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 4(t0)
    bne     t2, t3, test_fail

    fsw     f2, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 8(t0)
    bne     t2, t3, test_fail

    fsw     f3, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 12(t0)
    bne     t2, t3, test_fail

    fsw     f4, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 16(t0)
    bne     t2, t3, test_fail

    fsw     f5, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 20(t0)
    bne     t2, t3, test_fail

    fsw     f6, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 24(t0)
    bne     t2, t3, test_fail

    fsw     f7, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 28(t0)
    bne     t2, t3, test_fail

    fsw     f8, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 32(t0)
    bne     t2, t3, test_fail

    fsw     f9, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 36(t0)
    bne     t2, t3, test_fail

    fsw     f10, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 40(t0)
    bne     t2, t3, test_fail

    fsw     f11, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 44(t0)
    bne     t2, t3, test_fail

    fsw     f12, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 48(t0)
    bne     t2, t3, test_fail

    fsw     f13, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 52(t0)
    bne     t2, t3, test_fail

    fsw     f14, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 56(t0)
    bne     t2, t3, test_fail

    fsw     f15, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 60(t0)
    bne     t2, t3, test_fail

    fsw     f16, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 64(t0)
    bne     t2, t3, test_fail

    fsw     f17, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 68(t0)
    bne     t2, t3, test_fail

    fsw     f18, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 72(t0)
    bne     t2, t3, test_fail

    fsw     f19, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 76(t0)
    bne     t2, t3, test_fail

    fsw     f20, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 80(t0)
    bne     t2, t3, test_fail

    fsw     f21, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 84(t0)
    bne     t2, t3, test_fail

    fsw     f22, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 88(t0)
    bne     t2, t3, test_fail

    fsw     f23, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 92(t0)
    bne     t2, t3, test_fail

    fsw     f24, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 96(t0)
    bne     t2, t3, test_fail

    fsw     f25, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 100(t0)
    bne     t2, t3, test_fail

    fsw     f26, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 104(t0)
    bne     t2, t3, test_fail

    fsw     f27, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 108(t0)
    bne     t2, t3, test_fail

    fsw     f28, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 112(t0)
    bne     t2, t3, test_fail

    fsw     f29, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 116(t0)
    bne     t2, t3, test_fail

    fsw     f30, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 120(t0)
    bne     t2, t3, test_fail

    fsw     f31, 0(t1)
    lw      t2, 0(t1)
    lw      t3, 124(t0)
    bne     t2, t3, test_fail

    # Verify FCSR
    csrr    t2, fcsr
    li      t3, 0x00000055
    bne     t2, t3, test_fail

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
task_a_fp_context:
    .space 132              # 32 FP registers × 4 bytes + 4 bytes for FCSR

.align 4
task_b_fp_context:
    .space 132              # 32 FP registers × 4 bytes + 4 bytes for FCSR

.align 4
temp_storage:
    .space 4                # Temporary storage for comparisons

# Task A FP values: 1.0, 2.0, 3.0, ..., 32.0 (IEEE 754 single-precision)
.align 4
task_a_fp_values:
    .word 0x3f800000        # f0  = 1.0
    .word 0x40000000        # f1  = 2.0
    .word 0x40400000        # f2  = 3.0
    .word 0x40800000        # f3  = 4.0
    .word 0x40a00000        # f4  = 5.0
    .word 0x40c00000        # f5  = 6.0
    .word 0x40e00000        # f6  = 7.0
    .word 0x41000000        # f7  = 8.0
    .word 0x41100000        # f8  = 9.0
    .word 0x41200000        # f9  = 10.0
    .word 0x41300000        # f10 = 11.0
    .word 0x41400000        # f11 = 12.0
    .word 0x41500000        # f12 = 13.0
    .word 0x41600000        # f13 = 14.0
    .word 0x41700000        # f14 = 15.0
    .word 0x41800000        # f15 = 16.0
    .word 0x41880000        # f16 = 17.0
    .word 0x41900000        # f17 = 18.0
    .word 0x41980000        # f18 = 19.0
    .word 0x41a00000        # f19 = 20.0
    .word 0x41a80000        # f20 = 21.0
    .word 0x41b00000        # f21 = 22.0
    .word 0x41b80000        # f22 = 23.0
    .word 0x41c00000        # f23 = 24.0
    .word 0x41c80000        # f24 = 25.0
    .word 0x41d00000        # f25 = 26.0
    .word 0x41d80000        # f26 = 27.0
    .word 0x41e00000        # f27 = 28.0
    .word 0x41e80000        # f28 = 29.0
    .word 0x41f00000        # f29 = 30.0
    .word 0x41f80000        # f30 = 31.0
    .word 0x42000000        # f31 = 32.0

# Task B FP values: 100.0, 101.0, 102.0, ..., 131.0 (IEEE 754 single-precision)
.align 4
task_b_fp_values:
    .word 0x42c80000        # f0  = 100.0
    .word 0x42ca0000        # f1  = 101.0
    .word 0x42cc0000        # f2  = 102.0
    .word 0x42ce0000        # f3  = 103.0
    .word 0x42d00000        # f4  = 104.0
    .word 0x42d20000        # f5  = 105.0
    .word 0x42d40000        # f6  = 106.0
    .word 0x42d60000        # f7  = 107.0
    .word 0x42d80000        # f8  = 108.0
    .word 0x42da0000        # f9  = 109.0
    .word 0x42dc0000        # f10 = 110.0
    .word 0x42de0000        # f11 = 111.0
    .word 0x42e00000        # f12 = 112.0
    .word 0x42e20000        # f13 = 113.0
    .word 0x42e40000        # f14 = 114.0
    .word 0x42e60000        # f15 = 115.0
    .word 0x42e80000        # f16 = 116.0
    .word 0x42ea0000        # f17 = 117.0
    .word 0x42ec0000        # f18 = 118.0
    .word 0x42ee0000        # f19 = 119.0
    .word 0x42f00000        # f20 = 120.0
    .word 0x42f20000        # f21 = 121.0
    .word 0x42f40000        # f22 = 122.0
    .word 0x42f60000        # f23 = 123.0
    .word 0x42f80000        # f24 = 124.0
    .word 0x42fa0000        # f25 = 125.0
    .word 0x42fc0000        # f26 = 126.0
    .word 0x42fe0000        # f27 = 127.0
    .word 0x43000000        # f28 = 128.0
    .word 0x43010000        # f29 = 129.0
    .word 0x43020000        # f30 = 130.0
    .word 0x43030000        # f31 = 131.0
