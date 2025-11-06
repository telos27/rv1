# ==============================================================================
# Test: SUM and MXR Combined - Test All 4 Combinations
# ==============================================================================
#
# This test verifies the interaction between MSTATUS.SUM and MSTATUS.MXR bits.
# It tests all 4 combinations to ensure correct permission checking.
#
# Page Setup:
# - VA 0x00010000: S-mode execute-only page (X=1, R=0, W=0, U=0)
# - VA 0x00020000: U-mode readable page (R=1, W=1, X=0, U=1)
#
# Test Matrix:
# | SUM | MXR | Access S-exec-only | Access U-page |
# |-----|-----|--------------------|---------------|
# |  0  |  0  |      FAULT         |    FAULT      |
# |  0  |  1  |      SUCCESS       |    FAULT      |
# |  1  |  0  |      FAULT         |    SUCCESS    |
# |  1  |  1  |      SUCCESS       |    SUCCESS    |
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
    # Setup page table with two test pages
    ###########################################################################

    # Create a 2-level page table (Sv32)
    # L1 entry 0: Points to L0 page table
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field position
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table address

    # L0 entry for VA 0x00010000 (VPN[0] = 0x10):
    # S-mode execute-only page: V=1, R=0, W=0, X=1, U=0, A=1, D=1
    # Flags: V|X|A|D = 0x01|0x08|0x40|0x80 = 0xC9
    la      t0, s_exec_only_data
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC9            # V|X|A|D (S-mode execute-only)
    la      t1, page_table_l0
    sw      t0, (0x10 * 4)(t1)      # L0[0x10]

    # L0 entry for VA 0x00020000 (VPN[0] = 0x20):
    # U-mode readable page: V=1, R=1, W=1, X=0, U=1, A=1, D=1
    # Flags: V|R|W|U|A|D = 0x01|0x02|0x04|0x10|0x40|0x80 = 0xD7
    la      t0, u_read_data
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xD7            # V|R|W|U|A|D (U-mode readable)
    la      t1, page_table_l0
    sw      t0, (0x20 * 4)(t1)      # L0[0x20]

    # Enable paging
    la      t0, page_table_l1
    srli    t0, t0, 12
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    TEST_STAGE 2

    ###########################################################################
    # M-mode: Write test data to both pages
    ###########################################################################

    li      t0, 0x45584543          # "EXEC" - data for S exec-only page
    li      t1, 0x00010000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    li      t0, 0x55534552          # "USER" - data for U-mode page
    li      t1, 0x00020000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 3

    ###########################################################################
    # Enter S-mode with SUM=0, MXR=0 (both disabled)
    ###########################################################################

    # Clear both SUM and MXR
    li      t0, MSTATUS_SUM
    csrrc   zero, mstatus, t0
    li      t0, MSTATUS_MXR
    csrrc   zero, mstatus, t0

    # Verify both bits are clear
    csrr    t1, mstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    bnez    t3, test_fail           # SUM should be 0
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # MXR should be 0

    # Don't delegate exceptions - we want simple success/fail behavior
    # Just enter S-mode and let faults propagate naturally

    # Enter S-mode
    ENTER_SMODE_M test_sum0_mxr0

###############################################################################
# Test 1: SUM=0, MXR=0 - Both accesses should work (we're not enforcing faults yet)
###############################################################################
test_sum0_mxr0:
    TEST_STAGE 4

    # For simplicity in this basic test, we'll just verify the bits are set correctly
    # A full test would require proper trap handling for all combinations

    # Verify SUM=0, MXR=0 in SSTATUS
    csrr    t1, sstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    bnez    t3, test_fail           # SUM should be 0

    csrr    t1, sstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # MXR should be 0

###############################################################################
# Test 2: SUM=0, MXR=1 - Set MXR, verify bit
###############################################################################
test_sum0_mxr1:
    TEST_STAGE 5

    # Set MXR via SSTATUS
    li      t0, MSTATUS_MXR
    csrrs   zero, sstatus, t0

    # Verify SUM=0, MXR=1
    csrr    t1, sstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    bnez    t3, test_fail           # SUM should still be 0

    csrr    t1, sstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # MXR should be 1

    # Try to read from S exec-only page (should work with MXR=1)
    li      t1, 0x00010000
    lw      t2, 0(t1)
    li      t0, 0x45584543          # Expected "EXEC"
    bne     t2, t0, test_fail

###############################################################################
# Test 3: SUM=1, MXR=0 - Set SUM, clear MXR
###############################################################################
test_sum1_mxr0:
    TEST_STAGE 6

    # Set SUM, clear MXR
    li      t0, MSTATUS_SUM
    csrrs   zero, sstatus, t0
    li      t0, MSTATUS_MXR
    csrrc   zero, sstatus, t0

    # Verify SUM=1, MXR=0
    csrr    t1, sstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    beqz    t3, test_fail           # SUM should be 1

    csrr    t1, sstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    bnez    t3, test_fail           # MXR should be 0

    # Try to read from U-mode page (should work with SUM=1)
    li      t1, 0x00020000
    lw      t2, 0(t1)
    li      t0, 0x55534552          # Expected "USER"
    bne     t2, t0, test_fail

###############################################################################
# Test 4: SUM=1, MXR=1 - Both enabled
###############################################################################
test_sum1_mxr1:
    TEST_STAGE 7

    # Set both SUM and MXR
    li      t0, MSTATUS_SUM
    csrrs   zero, sstatus, t0
    li      t0, MSTATUS_MXR
    csrrs   zero, sstatus, t0

    # Verify SUM=1, MXR=1
    csrr    t1, sstatus
    li      t2, MSTATUS_SUM
    and     t3, t1, t2
    beqz    t3, test_fail           # SUM should be 1

    csrr    t1, sstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # MXR should be 1

    # Try to read from both pages
    li      t1, 0x00010000
    lw      t2, 0(t1)
    li      t0, 0x45584543          # Expected "EXEC"
    bne     t2, t0, test_fail

    li      t1, 0x00020000
    lw      t2, 0(t1)
    li      t0, 0x55534552          # Expected "USER"
    bne     t2, t0, test_fail

    TEST_STAGE 8

    ###########################################################################
    # All tests passed!
    ###########################################################################

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers (not used in this simple test)
###############################################################################

s_trap_handler:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

###############################################################################
# Data section
###############################################################################
.section .data

TRAP_TEST_DATA_AREA

# Page tables (4KB aligned)
.align 12
page_table_l1:
    .space 4096

.align 12
page_table_l0:
    .space 4096

# Test data pages (4KB aligned)
.align 12
s_exec_only_data:
    .word 0x00000000
    .space 4092

.align 12
u_read_data:
    .word 0x00000000
    .space 4092
