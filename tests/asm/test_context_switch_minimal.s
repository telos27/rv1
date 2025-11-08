# ==============================================================================
# Test: Minimal Context Switch - GPR Preservation
# ==============================================================================
#
# This test verifies that general-purpose registers (GPRs) are correctly
# preserved across context switches. This is fundamental for multitasking.
#
# Test Sequence:
# 1. Setup "Task A" with distinct values in all GPRs (x1-x31)
# 2. Save Task A context to memory
# 3. Setup "Task B" with different values in all GPRs
# 4. Save Task B context to memory
# 5. Restore Task A context from memory
# 6. Verify all Task A registers are correctly restored
# 7. Restore Task B context from memory
# 8. Verify all Task B registers are correctly restored
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
    # Setup Task A state - Load distinctive values into all GPRs
    ###########################################################################

    # Note: x0 is hardwired to zero, skip it
    # x1 (ra) through x31 (t6)
    li      x1,  0x00000001      # ra
    li      x2,  0x00000002      # sp (will use for context switching)
    li      x3,  0x00000003      # gp
    li      x4,  0x00000004      # tp
    li      x5,  0x00000005      # t0
    li      x6,  0x00000006      # t1
    li      x7,  0x00000007      # t2
    li      x8,  0x00000008      # s0/fp
    li      x9,  0x00000009      # s1
    li      x10, 0x0000000A      # a0
    li      x11, 0x0000000B      # a1
    li      x12, 0x0000000C      # a2
    li      x13, 0x0000000D      # a3
    li      x14, 0x0000000E      # a4
    li      x15, 0x0000000F      # a5
    li      x16, 0x00000010      # a6
    li      x17, 0x00000011      # a7
    li      x18, 0x00000012      # s2
    li      x19, 0x00000013      # s3
    li      x20, 0x00000014      # s4
    li      x21, 0x00000015      # s5
    li      x22, 0x00000016      # s6
    li      x23, 0x00000017      # s7
    li      x24, 0x00000018      # s8
    li      x25, 0x00000019      # s9
    li      x26, 0x0000001A      # s10
    li      x27, 0x0000001B      # s11
    li      x28, 0x0000001C      # t3
    li      x29, 0x0000001D      # t4
    li      x30, 0x0000001E      # t5
    li      x31, 0x0000001F      # t6

    TEST_STAGE 2

    ###########################################################################
    # Save Task A context to memory
    ###########################################################################

    # Use a temporary register to hold the save area address
    # We'll use t0 (x5) but save it first
    la      x5, task_a_context   # t0 = address of Task A save area

    # Save all registers (x1-x31) to Task A context
    # Skip x0 (hardwired zero)
    sw      x1,  0(x5)           # Save ra
    sw      x2,  4(x5)           # Save sp
    sw      x3,  8(x5)           # Save gp
    sw      x4,  12(x5)          # Save tp
    # x5 (t0) contains our address, we'll save it after
    sw      x6,  20(x5)          # Save t1
    sw      x7,  24(x5)          # Save t2
    sw      x8,  28(x5)          # Save s0
    sw      x9,  32(x5)          # Save s1
    sw      x10, 36(x5)          # Save a0
    sw      x11, 40(x5)          # Save a1
    sw      x12, 44(x5)          # Save a2
    sw      x13, 48(x5)          # Save a3
    sw      x14, 52(x5)          # Save a4
    sw      x15, 56(x5)          # Save a5
    sw      x16, 60(x5)          # Save a6
    sw      x17, 64(x5)          # Save a7
    sw      x18, 68(x5)          # Save s2
    sw      x19, 72(x5)          # Save s3
    sw      x20, 76(x5)          # Save s4
    sw      x21, 80(x5)          # Save s5
    sw      x22, 84(x5)          # Save s6
    sw      x23, 88(x5)          # Save s7
    sw      x24, 92(x5)          # Save s8
    sw      x25, 96(x5)          # Save s9
    sw      x26, 100(x5)         # Save s10
    sw      x27, 104(x5)         # Save s11
    sw      x28, 108(x5)         # Save t3
    sw      x29, 112(x5)         # Save t4
    sw      x30, 116(x5)         # Save t5
    sw      x31, 120(x5)         # Save t6
    # Now save t0 (x5) itself
    li      x6, 0x00000005       # Reload original t0 value
    sw      x6, 16(x5)           # Save t0

    TEST_STAGE 3

    ###########################################################################
    # Setup Task B state - Different values
    ###########################################################################

    li      x1,  0x10000001      # ra
    li      x2,  0x10000002      # sp
    li      x3,  0x10000003      # gp
    li      x4,  0x10000004      # tp
    li      x5,  0x10000005      # t0
    li      x6,  0x10000006      # t1
    li      x7,  0x10000007      # t2
    li      x8,  0x10000008      # s0
    li      x9,  0x10000009      # s1
    li      x10, 0x1000000A      # a0
    li      x11, 0x1000000B      # a1
    li      x12, 0x1000000C      # a2
    li      x13, 0x1000000D      # a3
    li      x14, 0x1000000E      # a4
    li      x15, 0x1000000F      # a5
    li      x16, 0x10000010      # a6
    li      x17, 0x10000011      # a7
    li      x18, 0x10000012      # s2
    li      x19, 0x10000013      # s3
    li      x20, 0x10000014      # s4
    li      x21, 0x10000015      # s5
    li      x22, 0x10000016      # s6
    li      x23, 0x10000017      # s7
    li      x24, 0x10000018      # s8
    li      x25, 0x10000019      # s9
    li      x26, 0x1000001A      # s10
    li      x27, 0x1000001B      # s11
    li      x28, 0x1000001C      # t3
    li      x29, 0x1000001D      # t4
    li      x30, 0x1000001E      # t5
    li      x31, 0x1000001F      # t6

    TEST_STAGE 4

    ###########################################################################
    # Save Task B context to memory
    ###########################################################################

    la      x5, task_b_context   # t0 = address of Task B save area

    sw      x1,  0(x5)
    sw      x2,  4(x5)
    sw      x3,  8(x5)
    sw      x4,  12(x5)
    sw      x6,  20(x5)
    sw      x7,  24(x5)
    sw      x8,  28(x5)
    sw      x9,  32(x5)
    sw      x10, 36(x5)
    sw      x11, 40(x5)
    sw      x12, 44(x5)
    sw      x13, 48(x5)
    sw      x14, 52(x5)
    sw      x15, 56(x5)
    sw      x16, 60(x5)
    sw      x17, 64(x5)
    sw      x18, 68(x5)
    sw      x19, 72(x5)
    sw      x20, 76(x5)
    sw      x21, 80(x5)
    sw      x22, 84(x5)
    sw      x23, 88(x5)
    sw      x24, 92(x5)
    sw      x25, 96(x5)
    sw      x26, 100(x5)
    sw      x27, 104(x5)
    sw      x28, 108(x5)
    sw      x29, 112(x5)
    sw      x30, 116(x5)
    sw      x31, 120(x5)
    li      x6, 0x10000005
    sw      x6, 16(x5)

    TEST_STAGE 5

    ###########################################################################
    # Restore Task A context and verify
    ###########################################################################

    la      x5, task_a_context

    lw      x1,  0(x5)
    lw      x2,  4(x5)
    lw      x3,  8(x5)
    lw      x4,  12(x5)
    lw      x6,  20(x5)
    lw      x7,  24(x5)
    lw      x8,  28(x5)
    lw      x9,  32(x5)
    lw      x10, 36(x5)
    lw      x11, 40(x5)
    lw      x12, 44(x5)
    lw      x13, 48(x5)
    lw      x14, 52(x5)
    lw      x15, 56(x5)
    lw      x16, 60(x5)
    lw      x17, 64(x5)
    lw      x18, 68(x5)
    lw      x19, 72(x5)
    lw      x20, 76(x5)
    lw      x21, 80(x5)
    lw      x22, 84(x5)
    lw      x23, 88(x5)
    lw      x24, 92(x5)
    lw      x25, 96(x5)
    lw      x26, 100(x5)
    lw      x27, 104(x5)
    lw      x28, 108(x5)
    lw      x29, 112(x5)
    lw      x30, 116(x5)
    lw      x31, 120(x5)
    lw      x5,  16(x5)          # Restore t0 last

    TEST_STAGE 6

    ###########################################################################
    # Verify Task A registers are correct
    ###########################################################################

    # Use temporary register for comparisons (we'll use t0/x5)
    # Note: Skip x3 (gp), x5 (t0), x29 (t4) as they're used by test infrastructure
    # Check each register against expected value
    li      t0, 0x00000001
    bne     x1, t0, test_fail
    li      t0, 0x00000002
    bne     x2, t0, test_fail
    # Skip x3 (gp) - used by test infrastructure
    li      t0, 0x00000004
    bne     x4, t0, test_fail
    # Skip x5 (t0) - we're using it for comparisons
    li      t0, 0x00000006
    bne     x6, t0, test_fail
    li      t0, 0x00000007
    bne     x7, t0, test_fail
    li      t0, 0x00000008
    bne     x8, t0, test_fail
    li      t0, 0x00000009
    bne     x9, t0, test_fail
    li      t0, 0x0000000A
    bne     x10, t0, test_fail
    li      t0, 0x0000000B
    bne     x11, t0, test_fail
    li      t0, 0x0000000C
    bne     x12, t0, test_fail
    li      t0, 0x0000000D
    bne     x13, t0, test_fail
    li      t0, 0x0000000E
    bne     x14, t0, test_fail
    li      t0, 0x0000000F
    bne     x15, t0, test_fail
    li      t0, 0x00000010
    bne     x16, t0, test_fail
    li      t0, 0x00000011
    bne     x17, t0, test_fail
    li      t0, 0x00000012
    bne     x18, t0, test_fail
    li      t0, 0x00000013
    bne     x19, t0, test_fail
    li      t0, 0x00000014
    bne     x20, t0, test_fail
    li      t0, 0x00000015
    bne     x21, t0, test_fail
    li      t0, 0x00000016
    bne     x22, t0, test_fail
    li      t0, 0x00000017
    bne     x23, t0, test_fail
    li      t0, 0x00000018
    bne     x24, t0, test_fail
    li      t0, 0x00000019
    bne     x25, t0, test_fail
    li      t0, 0x0000001A
    bne     x26, t0, test_fail
    li      t0, 0x0000001B
    bne     x27, t0, test_fail
    li      t0, 0x0000001C
    bne     x28, t0, test_fail
    # Skip x29 (t4) - used by TEST_STAGE macro
    li      t0, 0x0000001E
    bne     x30, t0, test_fail
    li      t0, 0x0000001F
    bne     x31, t0, test_fail

    TEST_STAGE 7

    ###########################################################################
    # Restore Task B context and verify
    ###########################################################################

    la      x5, task_b_context

    lw      x1,  0(x5)
    lw      x2,  4(x5)
    lw      x3,  8(x5)
    lw      x4,  12(x5)
    lw      x6,  20(x5)
    lw      x7,  24(x5)
    lw      x8,  28(x5)
    lw      x9,  32(x5)
    lw      x10, 36(x5)
    lw      x11, 40(x5)
    lw      x12, 44(x5)
    lw      x13, 48(x5)
    lw      x14, 52(x5)
    lw      x15, 56(x5)
    lw      x16, 60(x5)
    lw      x17, 64(x5)
    lw      x18, 68(x5)
    lw      x19, 72(x5)
    lw      x20, 76(x5)
    lw      x21, 80(x5)
    lw      x22, 84(x5)
    lw      x23, 88(x5)
    lw      x24, 92(x5)
    lw      x25, 96(x5)
    lw      x26, 100(x5)
    lw      x27, 104(x5)
    lw      x28, 108(x5)
    lw      x29, 112(x5)
    lw      x30, 116(x5)
    lw      x31, 120(x5)
    lw      x5,  16(x5)

    TEST_STAGE 8

    ###########################################################################
    # Verify Task B registers
    ###########################################################################

    # Skip x3 (gp), x5 (t0), x29 (t4) - used by test infrastructure
    li      t0, 0x10000001
    bne     x1, t0, test_fail
    li      t0, 0x10000002
    bne     x2, t0, test_fail
    # Skip x3 (gp)
    li      t0, 0x10000004
    bne     x4, t0, test_fail
    # Skip x5 (t0)
    li      t0, 0x10000006
    bne     x6, t0, test_fail
    li      t0, 0x10000007
    bne     x7, t0, test_fail
    li      t0, 0x10000008
    bne     x8, t0, test_fail
    li      t0, 0x10000009
    bne     x9, t0, test_fail
    li      t0, 0x1000000A
    bne     x10, t0, test_fail
    li      t0, 0x1000000B
    bne     x11, t0, test_fail
    li      t0, 0x1000000C
    bne     x12, t0, test_fail
    li      t0, 0x1000000D
    bne     x13, t0, test_fail
    li      t0, 0x1000000E
    bne     x14, t0, test_fail
    li      t0, 0x1000000F
    bne     x15, t0, test_fail
    li      t0, 0x10000010
    bne     x16, t0, test_fail
    li      t0, 0x10000011
    bne     x17, t0, test_fail
    li      t0, 0x10000012
    bne     x18, t0, test_fail
    li      t0, 0x10000013
    bne     x19, t0, test_fail
    li      t0, 0x10000014
    bne     x20, t0, test_fail
    li      t0, 0x10000015
    bne     x21, t0, test_fail
    li      t0, 0x10000016
    bne     x22, t0, test_fail
    li      t0, 0x10000017
    bne     x23, t0, test_fail
    li      t0, 0x10000018
    bne     x24, t0, test_fail
    li      t0, 0x10000019
    bne     x25, t0, test_fail
    li      t0, 0x1000001A
    bne     x26, t0, test_fail
    li      t0, 0x1000001B
    bne     x27, t0, test_fail
    li      t0, 0x1000001C
    bne     x28, t0, test_fail
    # Skip x29 (t4)
    li      t0, 0x1000001E
    bne     x30, t0, test_fail
    li      t0, 0x1000001F
    bne     x31, t0, test_fail

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
task_a_context:
    .space 128              # 32 registers × 4 bytes

.align 4
task_b_context:
    .space 128              # 32 registers × 4 bytes
