# ==============================================================================
# Test: Multi-Level Page Table Walk - Sv32 2-Level Translation
# ==============================================================================
#
# This test explicitly verifies that 2-level page table walks work correctly
# by creating multiple L1 entries (different megapages) and multiple L0 entries
# within each megapage.
#
# Page Table Structure:
# L1[576] → L0_table_0:  (VPN[1] = 0x240 for VA 0x90000000)
#   L0_table_0[0x00] → VA 0x90000000 → PA test_data_0
#   L0_table_0[0x01] → VA 0x90001000 → PA test_data_1
#
# L1[577] → L0_table_1:  (VPN[1] = 0x241 for VA 0x90400000)
#   L0_table_1[0x00] → VA 0x90400000 → PA test_data_2
#   L0_table_1[0x01] → VA 0x90401000 → PA test_data_3
#
# Note: Using high VAs (0x90000000+) to avoid address masking conflicts
#       with page table storage at PA 0x80001000-0x80003000
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

    # First: Identity map code region (VA 0x80000000 → PA 0x80000000)
    # L1 entry 512: Megapage mapping for code/data region
    # VPN[1] = 0x200 (entry 512 in L1 table), offset = 512*4 = 2048 = 0x800
    li      t0, 0x200000CF          # PPN=0x80000, flags=V|R|W|X|A|D
    la      t1, page_table_l1
    li      t2, 0x800               # Offset for L1[512]
    add     t1, t1, t2
    sw      t0, 0(t1)               # L1[512] = identity megapage

    # L1 entry 576: Points to L0_table_0 (VA range 0x90000000-0x903FFFFF)
    # VPN[1] = 0x240 (entry 576 in L1 table), offset = 576*4 = 2304 = 0x900
    la      t0, page_table_l0_0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    li      t2, 0x900               # Offset for L1[576]
    add     t1, t1, t2              # Add offset to base
    sw      t0, 0(t1)               # L1[576] = L0_table_0

    # L1 entry 577: Points to L0_table_1 (VA range 0x90400000-0x907FFFFF)
    # VPN[1] = 0x241 (entry 577 in L1 table), offset = 577*4 = 2308 = 0x904
    la      t0, page_table_l0_1
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    li      t2, 0x904               # Offset for L1[577]
    add     t1, t1, t2              # Add offset to base
    sw      t0, 0(t1)               # L1[577] = L0_table_1

    # L0_table_0 entry 0x00: VA 0x90000000 → test_data_0
    # VPN[0] = 0x000, Flags: V=1, R=1, W=1, X=0, U=0, A=1, D=1 = 0xC7
    la      t0, test_data_0
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_0
    sw      t0, (0x00 * 4)(t1)      # L0_0[0x00]

    # L0_table_0 entry 0x01: VA 0x90001000 → test_data_1
    # VPN[0] = 0x001
    la      t0, test_data_1
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_0
    sw      t0, (0x01 * 4)(t1)      # L0_0[0x01]

    # L0_table_1 entry 0x00: VA 0x90400000 → test_data_2
    # VPN[0] = 0x000
    la      t0, test_data_2
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_1
    sw      t0, (0x00 * 4)(t1)      # L0_1[0x00]

    # L0_table_1 entry 0x01: VA 0x90401000 → test_data_3
    # VPN[0] = 0x001
    la      t0, test_data_3
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0_1
    sw      t0, (0x01 * 4)(t1)      # L0_1[0x01]

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

    # Write to VA 0x90000000 (L1[576], L0_0[0x00])
    li      t0, 0x11111111
    li      t1, 0x90000000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x90001000 (L1[576], L0_0[0x01])
    li      t0, 0x22222222
    li      t1, 0x90001000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x90400000 (L1[577], L0_1[0x00])
    li      t0, 0x33333333
    li      t1, 0x90400000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x90401000 (L1[577], L0_1[0x01])
    li      t0, 0x44444444
    li      t1, 0x90401000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 3

    ###########################################################################
    # Verify all four pages still have correct data
    ###########################################################################

    # Read from VA 0x90000000
    li      t1, 0x90000000
    lw      t2, 0(t1)
    li      t0, 0x11111111
    bne     t0, t2, test_fail

    # Read from VA 0x90001000
    li      t1, 0x90001000
    lw      t2, 0(t1)
    li      t0, 0x22222222
    bne     t0, t2, test_fail

    # Read from VA 0x90400000
    li      t1, 0x90400000
    lw      t2, 0(t1)
    li      t0, 0x33333333
    bne     t0, t2, test_fail

    # Read from VA 0x90401000
    li      t1, 0x90401000
    lw      t2, 0(t1)
    li      t0, 0x44444444
    bne     t0, t2, test_fail

    TEST_STAGE 4

    ###########################################################################
    # Test with offsets to verify page boundaries
    ###########################################################################

    # Write to VA 0x90000004 (offset +4 in first page)
    li      t0, 0xAAAAAAAA
    li      t1, 0x90000004
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x90000000
    lw      t2, 0(t1)
    li      t0, 0x11111111
    bne     t0, t2, test_fail

    # Write to VA 0x90401008 (offset +8 in fourth page)
    li      t0, 0xBBBBBBBB
    li      t1, 0x90401008
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x90401000
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

# Test data pages (4KB aligned, but only allocate 16 bytes each to save space)
# Note: In real use these would be full 4KB pages, but for testing we only
# need a few bytes per page to verify the MMU translation works correctly
.align 12
test_data_0:
    .space 16

.align 12
test_data_1:
    .space 16

.align 12
test_data_2:
    .space 16

.align 12
test_data_3:
    .space 16
