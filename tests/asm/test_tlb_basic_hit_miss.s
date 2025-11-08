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

    # Create page table with identity megapages
    # This test focuses on TLB hit/miss behavior, not complex page table walks
    la      t1, page_table_l1

    # L1 entry 512: Identity megapage for code/data region
    # VA 0x80000000-0x803FFFFF → PA 0x80000000-0x803FFFFF (4MB megapage)
    # This maps all code and data (code at 0x80000xxx, data at 0x80003xxx-0x80005xxx)
    # PPN = 0x80000000 >> 12 = 0x80000
    # PTE = (0x80000 << 10) | 0xCF = 0x20000000 | 0xCF
    li      t0, 0x200000CF          # Megapage: V|R|W|X|A|D
    li      t2, 2048                # Offset for L1[512] (512*4 bytes)
    add     t2, t1, t2              # Calculate address of L1[512]
    sw      t0, 0(t2)               # Store megapage PTE

    # Prepare SATP value (but don't enable yet - M-mode bypasses MMU)
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    mv      s0, t0                  # Save SATP value to s0

    # Enter S-mode (required for MMU/TLB to be active)
    ENTER_SMODE_M smode_entry

smode_entry:
    # Now in S-mode - enable paging with SATP
    csrw    satp, s0
    sfence.vma                      # Flush TLB (start clean)

    TEST_STAGE 2

    ###########################################################################
    # First access - TLB miss (loads translation into TLB)
    ###########################################################################

    # Write test data through identity-mapped VA (VA = PA for test_data)
    li      t0, 0xDEADBEEF
    la      t1, test_data           # VA 0x80005000 → PA 0x80005000 (identity)
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
    la      t1, test_data
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
    la      t1, test_data
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
    la      t1, test_data
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

    # Invalidate specific VA (test_data address)
    la      a0, test_data
    sfence.vma a0, zero             # Invalidate specific VA, all ASIDs

    # Access after specific invalidation
    li      t0, 0x55555555
    la      t1, test_data
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
    # Check if this is an intentional ebreak (from TEST_PASS/TEST_FAIL)
    # If x28 already has a result marker, just ebreak again to exit
    li      t0, 0xDEADBEEF
    beq     x28, t0, 1f         # If x28 = PASS marker, exit
    li      t0, 0xDEADDEAD
    beq     x28, t0, 1f         # If x28 = FAIL marker, exit
    # Otherwise, this is an unexpected trap - mark as failure
    TEST_FAIL
1:  ebreak                      # Re-execute ebreak to let testbench catch it

m_trap_handler:
    # Check if this is an intentional ebreak (from TEST_PASS/TEST_FAIL)
    # If x28 already has a result marker, just ebreak again to exit
    li      t0, 0xDEADBEEF
    beq     x28, t0, 1f         # If x28 = PASS marker, exit
    li      t0, 0xDEADDEAD
    beq     x28, t0, 1f         # If x28 = FAIL marker, exit
    # Otherwise, this is an unexpected trap - mark as failure
    TEST_FAIL
1:  ebreak                      # Re-execute ebreak to let testbench catch it

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
