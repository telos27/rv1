# ==============================================================================
# Test: Virtual Memory with Multiple Identity-Mapped Pages (Sv32)
# ==============================================================================
#
# This test verifies:
# 1. Multiple pages can be mapped and accessed independently
# 2. TLB can handle multiple translations correctly
# 3. Each page maintains its own data correctly
# 4. Page table walk works for different VPN indices
#
# Approach:
# - Start in M-mode, set up 4 identity-mapped pages in different regions
# - Enter S-mode and enable Sv32 paging
# - Access each page with unique test patterns
# - Verify all pages work independently and correctly
#
# This is Phase 2, Priority 1A: Multi-page VM test with identity mapping
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

# ==============================================================================
# Page Table Constants
# ==============================================================================

# Sv32 SATP MODE field (bit 31)
.equ SATP_MODE_SV32,    0x80000000

# PTE flags (bits 7:0)
.equ PTE_V,     (1 << 0)    # Valid
.equ PTE_R,     (1 << 1)    # Readable
.equ PTE_W,     (1 << 2)    # Writable
.equ PTE_X,     (1 << 3)    # Executable
.equ PTE_U,     (1 << 4)    # User accessible
.equ PTE_G,     (1 << 5)    # Global
.equ PTE_A,     (1 << 6)    # Accessed
.equ PTE_D,     (1 << 7)    # Dirty

# Combined flags for supervisor rwx page
.equ PTE_SUPERVISOR_RWX,  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)

# Test patterns for each page
.equ PATTERN_PAGE1, 0x11111111
.equ PATTERN_PAGE2, 0x22222222
.equ PATTERN_PAGE3, 0x33333333
.equ PATTERN_PAGE4, 0x44444444

# Physical addresses within 16KB DMEM range (0x80000000 - 0x80003FFF)
# We'll use 4KB pages within this range
.equ PA_REGION1, 0x80002000  # Page at offset 0x2000 (8KB)
.equ PA_REGION2, 0x80003000  # Page at offset 0x3000 (12KB)
.equ PA_REGION3, 0x80002800  # Page at offset 0x2800 (10KB)
.equ PA_REGION4, 0x80003800  # Page at offset 0x3800 (14KB)

# ==============================================================================
# Data Section - Page Table and Test Data
# ==============================================================================

.section .data
.align 12  # 4KB alignment for page table

page_table_l1:
    # Entry 0: Maps VA 0x00000000-0x003FFFFF (4MB megapage) to PA 0x80000000
    # For Sv32 megapages: PTE format is [31:10] = PPN (22 bits), [9:0] = flags
    # Target PA = 0x80000000
    # PPN = PA[33:12] = 0x80000000 >> 12 = 0x80000 (22 bits)
    # PTE = (PPN << 10) | flags = (0x80000 << 10) | 0xCF = 0x20000000 | 0xCF = 0x200000CF
    .word 0x200000CF

    # Entry 1: Maps VA 0x00400000-0x007FFFFF → PA 0x80000000 (same as entry 0)
    # This creates multiple VAs mapping to same PA region for TLB testing
    .word 0x200000CF

    # Entry 2: Maps VA 0x00800000-0x00BFFFFF → PA 0x80000000
    .word 0x200000CF

    # Entry 3: Maps VA 0x00C00000-0x00FFFFFF → PA 0x80000000
    .word 0x200000CF

    # Entries 4-511: Invalid
    .fill 508, 4, 0x00000000

    # Entry 512: Maps VA 0x80000000-0x803FFFFF (4MB megapage) to PA 0x80000000
    # This is where our code is actually loaded (linker script puts it at 0x80000000)
    # VPN[1] = VA[31:22] = 0x200 (entry index 512)
    # Same PPN as entry 0 (both map to PA 0x80000000)
    # PTE = 0x200000CF
    .word 0x200000CF

    # Entries 513-1023: Invalid
    .fill 511, 4, 0x00000000

# Test data areas - allocated in .data section within DMEM
# These will be at physical addresses 0x80002000+
.align 4
test_data_region1:
    .word 0x00000000

.align 4
test_data_region2:
    .word 0x00000000

.align 4
test_data_region3:
    .word 0x00000000

.align 4
test_data_region4:
    .word 0x00000000

# ==============================================================================
# Text Section - Test Code
# ==============================================================================

.section .text
.globl _start

_start:
    # We start in M-mode
    TEST_STAGE 1

    ###########################################################################
    # STAGE 1: Verify initial state (M-mode, no paging)
    ###########################################################################

    # Verify SATP is initially 0 (bare mode)
    csrr    t0, satp
    bnez    t0, test_fail

    # Verify basic memory access works to each test region
    li      t1, PATTERN_PAGE1
    la      t2, test_data_region1
    sw      t1, 0(t2)
    lw      t3, 0(t2)
    bne     t1, t3, test_fail

    TEST_STAGE 2

    ###########################################################################
    # STAGE 2: Setup page table and SATP (still in M-mode)
    ###########################################################################

    # Calculate PPN of root page table
    la      t0, page_table_l1
    srli    t0, t0, 12          # Convert PA to PPN (PA >> 12)

    # Create SATP value: MODE=1 (Sv32), ASID=0, PPN=page_table_l1
    # SATP format for Sv32: [31]=MODE, [30:22]=ASID, [21:0]=PPN
    li      t1, SATP_MODE_SV32
    or      t0, t0, t1

    # Save SATP value for later (we'll write it in S-mode)
    mv      s0, t0

    TEST_STAGE 3

    ###########################################################################
    # STAGE 3: Enter S-mode and enable paging
    ###########################################################################

    # Set up S-mode trap vector
    SET_STVEC_DIRECT s_trap_handler

    # Enter S-mode
    ENTER_SMODE_M smode_entry

smode_entry:
    # Now in S-mode
    TEST_STAGE 4

    # Write SATP to enable Sv32 paging
    csrw    satp, s0

    # Issue fence to flush TLB and ensure page table is visible
    sfence.vma

    # Verify SATP was written correctly
    csrr    t1, satp
    bne     t1, s0, test_fail

    TEST_STAGE 5

    ###########################################################################
    # STAGE 5: Test access to first mapped page (0x00000000 region)
    ###########################################################################

    # Write unique pattern to region 1
    li      t1, PATTERN_PAGE1
    la      t2, test_data_region1
    sw      t1, 0(t2)

    # Read back and verify
    lw      t3, 0(t2)
    bne     t1, t3, test_fail

    # Write second value to verify independence
    li      t4, 0xAABBCCDD
    sw      t4, 0(t2)
    lw      t5, 0(t2)
    bne     t4, t5, test_fail

    TEST_STAGE 6

    ###########################################################################
    # STAGE 6: Test TLB with multiple VAs mapping to same PA
    ###########################################################################

    # Key test: We'll access test_data_region2 through different VAs
    # Since all VPN[1] entries (0-3) map to PA 0x80000000, we can access
    # the same physical memory through different virtual addresses

    # Get physical address of region 2
    la      t0, test_data_region2
    # Calculate offset within the 4MB region
    li      t1, 0x003FFFFF
    and     t2, t0, t1          # t2 = offset within megapage

    # Write unique pattern via VA range 0 (0x00000000 + offset)
    li      t3, PATTERN_PAGE2
    or      t4, zero, t2        # VA = 0x00000000 | offset
    sw      t3, 0(t4)

    # Read back via same VA and verify
    lw      t5, 0(t4)
    bne     t3, t5, test_fail

    # Verify region 1 still has its data
    la      t6, test_data_region1
    lw      a0, 0(t6)
    li      a1, 0xAABBCCDD      # Last value written to region 1
    bne     a0, a1, test_fail

    TEST_STAGE 7

    ###########################################################################
    # STAGE 7: Access same PA through different VA (TLB entry 2)
    ###########################################################################

    # Read the same physical location via VA range 1 (0x00400000 + offset)
    # This forces a new TLB entry for VPN[1]=1
    li      t0, 0x00400000
    or      t1, t0, t2          # VA = 0x00400000 | offset
    lw      t3, 0(t1)

    # Should read the same value we wrote via VA range 0
    li      t4, PATTERN_PAGE2
    bne     t3, t4, test_fail

    # Now write a new value via VA range 1
    li      t5, 0x55555555
    sw      t5, 0(t1)

    # Read back via VA range 0 - should see the new value
    la      t6, test_data_region2
    li      a0, 0x003FFFFF
    and     a1, t6, a0
    lw      a2, 0(a1)
    bne     a2, t5, test_fail

    TEST_STAGE 8

    ###########################################################################
    # STAGE 8: Access same PA through third VA (TLB entry 3)
    ###########################################################################

    # Access via VA range 2 (0x00800000 + offset)
    li      t0, 0x00800000
    or      t1, t0, t2          # VA = 0x00800000 | offset
    lw      t3, 0(t1)

    # Should still see the value from stage 7
    li      t4, 0x55555555
    bne     t3, t4, test_fail

    # Write another new value via VA range 2
    li      t5, PATTERN_PAGE3
    sw      t5, 0(t1)

    # Verify via VA range 1
    li      t0, 0x00400000
    or      t1, t0, t2
    lw      t3, 0(t1)
    bne     t3, t5, test_fail

    TEST_STAGE 9

    ###########################################################################
    # STAGE 9: Access same PA through fourth VA (TLB entry 4)
    ###########################################################################

    # Access via VA range 3 (0x00C00000 + offset)
    li      t0, 0x00C00000
    or      t1, t0, t2          # VA = 0x00C00000 | offset
    lw      t3, 0(t1)

    # Should see the value from stage 8
    li      t4, PATTERN_PAGE3
    bne     t3, t4, test_fail

    # Write final pattern via VA range 3
    li      t5, PATTERN_PAGE4
    sw      t5, 0(t1)

    # Verify we can read it back via VA range 0
    la      t6, test_data_region2
    li      a0, 0x003FFFFF
    and     a1, t6, a0
    lw      a2, 0(a1)
    li      a3, PATTERN_PAGE4
    bne     a2, a3, test_fail

    TEST_STAGE 10

    ###########################################################################
    # STAGE 10: Verify TLB has multiple entries (stress test)
    ###########################################################################

    # Now we have 4+ TLB entries (VPN[1] = 0, 1, 2, 3, plus entry 512 for code)
    # Access all of them in quick succession to verify they're all cached

    # Write unique values to different test regions via different VAs
    li      t0, 0xDEADBEEF
    la      t1, test_data_region1
    sw      t0, 0(t1)

    li      t0, 0xCAFEBABE
    la      t1, test_data_region3
    li      t3, 0x003FFFFF
    and     t4, t1, t3
    li      t5, 0x00400000      # Access region3 via VA range 1
    or      t6, t5, t4
    sw      t0, 0(t6)

    li      t0, 0xFEEDFACE
    la      t1, test_data_region4
    and     t4, t1, t3
    li      t5, 0x00800000      # Access region4 via VA range 2
    or      t6, t5, t4
    sw      t0, 0(t6)

    # Read back all values via original VAs
    la      t0, test_data_region1
    lw      t1, 0(t0)
    li      t2, 0xDEADBEEF
    bne     t1, t2, test_fail

    la      t0, test_data_region3
    and     t4, t0, t3
    li      t5, 0x00400000
    or      t6, t5, t4
    lw      t1, 0(t6)
    li      t2, 0xCAFEBABE
    bne     t1, t2, test_fail

    la      t0, test_data_region4
    and     t4, t0, t3
    li      t5, 0x00800000
    or      t6, t5, t4
    lw      t1, 0(t6)
    li      t2, 0xFEEDFACE
    bne     t1, t2, test_fail

    TEST_STAGE 11

    ###########################################################################
    # STAGE 11: Disable paging and verify physical access still works
    ###########################################################################

    # Set SATP.MODE = 0 (bare mode)
    csrw    satp, zero
    sfence.vma

    # Verify SATP is now 0
    csrr    t0, satp
    bnez    t0, test_fail

    # Test memory access in bare mode (physical addresses)
    li      a0, 0xCAFEBABE
    la      a1, test_data_region1
    sw      a0, 0(a1)
    lw      a2, 0(a1)
    bne     a0, a2, test_fail

    TEST_STAGE 12

    ###########################################################################
    # SUCCESS
    ###########################################################################
    TEST_PASS

test_fail:
    TEST_FAIL

# ==============================================================================
# Trap Handlers
# ==============================================================================

.align 4
s_trap_handler:
    # Unexpected trap in S-mode = test failure
    # Save cause for debugging
    csrr    t0, scause
    csrr    t1, sepc
    csrr    t2, stval
    j       test_fail

# Trap data area
TRAP_TEST_DATA_AREA
