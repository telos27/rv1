# ==============================================================================
# Test: Multi-Level Page Table Walk - Sv32 2-Level Translation
# ==============================================================================
#
# This test explicitly verifies that 2-level page table walks work correctly
# by creating multiple L1 entries (different megapages) and multiple L0 entries
# within each megapage.
#
# Page Table Structure:
# L1[0] → L0_table_0:
#   L0_table_0[0x10] → VA 0x00010000 → PA test_data_0
#   L0_table_0[0x20] → VA 0x00020000 → PA test_data_1
#
# L1[1] → L0_table_1:
#   L0_table_1[0x10] → VA 0x00410000 → PA test_data_2
#   L0_table_1[0x20] → VA 0x00420000 → PA test_data_3
#
# This ensures the MMU correctly:
# - Walks through L1 using VPN[1]
# - Walks through the correct L0 table using VPN[0]
# - Constructs the correct physical address
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
    # Setup 2-level page table with multiple L1 and L0 entries
    ###########################################################################

    # L1 entry 0: Points to L0_table_0 (VA range 0x00000000-0x003FFFFF)
    la      t0, page_table_l0_0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0_table_0

    # L1 entry 1: Points to L0_table_1 (VA range 0x00400000-0x007FFFFF)
    la      t0, page_table_l0_1
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 4(t1)               # L1[1] = L0_table_1

    # L0_table_0 entry 0x10: VA 0x00010000 → test_data_0
    # Flags: V=1, R=1, W=1, X=0, U=0, A=1, D=1 = 0xC7
    la      t0, test_data_0
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_0
    sw      t0, (0x10 * 4)(t1)      # L0_0[0x10]

    # L0_table_0 entry 0x20: VA 0x00020000 → test_data_1
    la      t0, test_data_1
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_0
    sw      t0, (0x20 * 4)(t1)      # L0_0[0x20]

    # L0_table_1 entry 0x10: VA 0x00410000 → test_data_2
    la      t0, test_data_2
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_1
    sw      t0, (0x10 * 4)(t1)      # L0_1[0x10]

    # L0_table_1 entry 0x20: VA 0x00420000 → test_data_3
    la      t0, test_data_3
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_1
    sw      t0, (0x20 * 4)(t1)      # L0_1[0x20]

    # Enable paging with SATP
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma                      # Flush TLB

    TEST_STAGE 2

    ###########################################################################
    # M-mode: Write test patterns to all four pages
    ###########################################################################

    # Write to VA 0x00010000 (L1[0], L0_0[0x10])
    li      t0, 0x11111111
    li      t1, 0x00010000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x00020000 (L1[0], L0_0[0x20])
    li      t0, 0x22222222
    li      t1, 0x00020000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x00410000 (L1[1], L0_1[0x10])
    li      t0, 0x33333333
    li      t1, 0x00410000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x00420000 (L1[1], L0_1[0x20])
    li      t0, 0x44444444
    li      t1, 0x00420000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 3

    ###########################################################################
    # Verify all four pages still have correct data
    ###########################################################################

    # Read from VA 0x00010000
    li      t1, 0x00010000
    lw      t2, 0(t1)
    li      t0, 0x11111111
    bne     t0, t2, test_fail

    # Read from VA 0x00020000
    li      t1, 0x00020000
    lw      t2, 0(t1)
    li      t0, 0x22222222
    bne     t0, t2, test_fail

    # Read from VA 0x00410000
    li      t1, 0x00410000
    lw      t2, 0(t1)
    li      t0, 0x33333333
    bne     t0, t2, test_fail

    # Read from VA 0x00420000
    li      t1, 0x00420000
    lw      t2, 0(t1)
    li      t0, 0x44444444
    bne     t0, t2, test_fail

    TEST_STAGE 4

    ###########################################################################
    # Test with offsets to verify page boundaries
    ###########################################################################

    # Write to VA 0x00010004 (offset +4 in first page)
    li      t0, 0xAAAAAAAA
    li      t1, 0x00010004
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x00010000
    lw      t2, 0(t1)
    li      t0, 0x11111111
    bne     t0, t2, test_fail

    # Write to VA 0x00420008 (offset +8 in fourth page)
    li      t0, 0xBBBBBBBB
    li      t1, 0x00420008
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x00420000
    lw      t2, 0(t1)
    li      t0, 0x44444444
    bne     t0, t2, test_fail

    TEST_STAGE 5

    ###########################################################################
    # All tests passed!
    ###########################################################################

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers (not used)
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
page_table_l0_0:
    .space 4096

.align 12
page_table_l0_1:
    .space 4096

# Test data pages (4KB aligned)
.align 12
test_data_0:
    .word 0x00000000
    .space 4092

.align 12
test_data_1:
    .word 0x00000000
    .space 4092

.align 12
test_data_2:
    .word 0x00000000
    .space 4092

.align 12
test_data_3:
    .word 0x00000000
    .space 4092
