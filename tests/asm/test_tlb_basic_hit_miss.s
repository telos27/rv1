# ==============================================================================
# Test: TLB Basic Hit/Miss - Verify TLB Caching Behavior
# ==============================================================================
#
# This test verifies that the TLB correctly caches translations and that
# SFENCE.VMA properly invalidates TLB entries.
#
# Test Sequence:
# 1. Setup page table with a test page
# 2. Access the page (causes TLB miss, loads translation)
# 3. Access again (TLB hit, uses cached translation)
# 4. Execute SFENCE.VMA
# 5. Access again (TLB miss, reloads translation)
#
# Note: This is a basic test that verifies TLB functionality exists.
# Actual TLB hit/miss behavior cannot be directly observed without
# performance counters, so we verify correct functionality.
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
    # Setup page table with test page
    ###########################################################################

    # Create a 2-level page table (Sv32)
    # L1 entry 0: Points to L0 page table
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table

    # L0 entry 0x10: VA 0x00010000 → test_data
    # Flags: V=1, R=1, W=1, X=0, U=0, A=1, D=1 = 0xC7
    la      t0, test_data
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0
    sw      t0, (0x10 * 4)(t1)      # L0[0x10] for VA 0x00010000

    # Enable paging with SATP
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma                      # Flush TLB (start clean)

    TEST_STAGE 2

    ###########################################################################
    # First access - TLB miss (loads translation into TLB)
    ###########################################################################

    # Write test data through VA 0x00010000
    li      t0, 0xDEADBEEF
    li      t1, 0x00010000
    sw      t0, 0(t1)               # TLB miss → PTW → TLB load

    # Read back and verify
    lw      t2, 0(t1)               # Should be TLB hit now
    bne     t0, t2, test_fail

    TEST_STAGE 3

    ###########################################################################
    # Second access - TLB hit (uses cached translation)
    ###########################################################################

    # Access same VA again - should use cached TLB entry
    li      t0, 0xCAFEBABE
    li      t1, 0x00010000
    sw      t0, 0(t1)               # TLB hit (fast)

    # Read back and verify
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 4

    ###########################################################################
    # Execute SFENCE.VMA to flush TLB
    ###########################################################################

    sfence.vma                      # Invalidate all TLB entries

    TEST_STAGE 5

    ###########################################################################
    # Third access - TLB miss again (TLB was flushed)
    ###########################################################################

    # Access same VA after SFENCE - should be TLB miss again
    li      t0, 0x12345678
    li      t1, 0x00010000
    sw      t0, 0(t1)               # TLB miss → PTW → TLB reload

    # Read back and verify
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 6

    ###########################################################################
    # Fourth access - TLB hit (cached again after reload)
    ###########################################################################

    # Access same VA again - should use newly cached entry
    li      t0, 0xABCDEF00
    li      t1, 0x00010000
    sw      t0, 0(t1)               # TLB hit

    # Read back and verify
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 7

    ###########################################################################
    # Test SFENCE.VMA with specific VA and ASID
    ###########################################################################

    # SFENCE.VMA rs1, rs2 where:
    # - rs1 = VA to invalidate (or x0 for all)
    # - rs2 = ASID (or x0 for all)

    # Invalidate specific VA (0x00010000)
    li      a0, 0x00010000
    sfence.vma a0, zero             # Invalidate VA 0x00010000, all ASIDs

    # Access after specific invalidation
    li      t0, 0x55555555
    li      t1, 0x00010000
    sw      t0, 0(t1)               # TLB miss → PTW → reload

    # Read back and verify
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 8

    ###########################################################################
    # All tests passed!
    ###########################################################################

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers
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

# Test data page (4KB aligned)
.align 12
test_data:
    .word 0x00000000
    .space 4092
