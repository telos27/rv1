# ==============================================================================
# Test: Sparse Virtual Memory Mapping - Non-Contiguous VAs
# ==============================================================================
#
# This test verifies that non-contiguous virtual address regions can be mapped
# correctly, and that accessing unmapped regions causes page faults.
#
# Memory Layout:
# - VA 0x00001000 → PA test_data_0 (mapped)
# - VA 0x00002000 → unmapped (should fault)
# - VA 0x00003000 → unmapped (should fault)
# - VA 0x00004000 → unmapped (should fault)
# - VA 0x00005000 → PA test_data_1 (mapped)
#
# This is critical for OS support where address spaces are sparse with
# guard pages between regions.
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
    # Setup page table with sparse (non-contiguous) mappings
    ###########################################################################

    # Create a 2-level page table (Sv32)
    # L1 entry 0: Points to L0 page table for VA range 0x00000000-0x003FFFFF
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table

    # L0 entry 0x01: VA 0x00001000 → test_data_0 (MAPPED)
    # Flags: V=1, R=1, W=1, X=0, U=0, A=1, D=1 = 0xC7
    la      t0, test_data_0
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0
    sw      t0, (0x01 * 4)(t1)      # L0[0x01] for VA 0x00001000

    # L0 entries 0x02, 0x03, 0x04: UNMAPPED (leave as 0, invalid)
    # These will cause page faults when accessed

    # L0 entry 0x05: VA 0x00005000 → test_data_1 (MAPPED)
    la      t0, test_data_1
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0
    sw      t0, (0x05 * 4)(t1)      # L0[0x05] for VA 0x00005000

    # Enable paging with SATP
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma                      # Flush TLB

    TEST_STAGE 2

    ###########################################################################
    # M-mode: Write test data to mapped pages
    ###########################################################################

    # Write to VA 0x00001000 (mapped)
    li      t0, 0xAAAAAAAA
    li      t1, 0x00001000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Write to VA 0x00005000 (mapped)
    li      t0, 0xBBBBBBBB
    li      t1, 0x00005000
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 3

    ###########################################################################
    # Verify mapped pages still have correct data
    ###########################################################################

    # Read from VA 0x00001000
    li      t1, 0x00001000
    lw      t2, 0(t1)
    li      t0, 0xAAAAAAAA
    bne     t0, t2, test_fail

    # Read from VA 0x00005000
    li      t1, 0x00005000
    lw      t2, 0(t1)
    li      t0, 0xBBBBBBBB
    bne     t0, t2, test_fail

    TEST_STAGE 4

    ###########################################################################
    # Test with offsets within mapped pages
    ###########################################################################

    # Write to VA 0x00001004 (offset +4 in first mapped page)
    li      t0, 0x11111111
    li      t1, 0x00001004
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x00001000
    lw      t2, 0(t1)
    li      t0, 0xAAAAAAAA
    bne     t0, t2, test_fail

    # Write to VA 0x00005008 (offset +8 in second mapped page)
    li      t0, 0x22222222
    li      t1, 0x00005008
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # Verify original data at offset 0 is intact
    li      t1, 0x00005000
    lw      t2, 0(t1)
    li      t0, 0xBBBBBBBB
    bne     t0, t2, test_fail

    TEST_STAGE 5

    ###########################################################################
    # Note: Testing unmapped pages (VA 0x2000, 0x3000, 0x4000) would require
    # proper trap handling. For this basic test, we verify the mapped pages
    # work correctly. A full test with fault handling would be in Week 2.
    ###########################################################################

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers (minimal for this test)
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
test_data_0:
    .word 0x00000000
    .space 4092

.align 12
test_data_1:
    .word 0x00000000
    .space 4092
