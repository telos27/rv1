# ==============================================================================
# Test: Basic Virtual Memory with Identity Mapping (Sv32)
# ==============================================================================
#
# This test verifies:
# 1. SATP can be written and MODE field is set correctly
# 2. Page table walk works with a single identity-mapped page
# 3. Loads/stores work through the TLB with identity mapping
# 4. Disabling VM returns to physical addressing
#
# Approach:
# - Start in M-mode, set up a simple 1-page identity mapping
# - Enter S-mode and enable Sv32 paging
# - Perform memory operations through the MMU (VA == PA)
# - Disable paging and verify physical access still works
#
# This is Phase 2, Priority 1A: Simple VM test with identity mapping
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

# ==============================================================================
# Data Section - Page Table
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

    # Entries 1-511: Invalid
    .fill 511, 4, 0x00000000

    # Entry 512: Maps VA 0x80000000-0x803FFFFF (4MB megapage) to PA 0x80000000
    # This is where our code is actually loaded (linker script puts it at 0x80000000)
    # VPN[1] = VA[31:22] = 0x200 (entry index 512)
    # Same PPN as entry 0 (both map to PA 0x80000000)
    # PTE = 0x200000CF
    .word 0x200000CF

    # Entries 513-1023: Invalid
    .fill 511, 4, 0x00000000

# Test data area
.align 4
test_data:
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

    # Verify basic memory access works
    li      t1, 0x12345678
    la      t2, test_data
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
    # STAGE 5: Test memory access with paging enabled (identity mapping)
    ###########################################################################

    # Write a value through the MMU
    li      t2, 0xABCD1234
    la      t3, test_data
    sw      t2, 0(t3)

    # Read it back
    lw      t4, 0(t3)
    bne     t2, t4, test_fail

    # Try a different value
    li      t5, 0xDEADC0DE
    sw      t5, 0(t3)
    lw      t6, 0(t3)
    bne     t5, t6, test_fail

    TEST_STAGE 6

    ###########################################################################
    # STAGE 6: Disable paging and verify physical access
    ###########################################################################

    # Set SATP.MODE = 0 (bare mode)
    csrw    satp, zero
    sfence.vma

    # Verify SATP is now 0
    csrr    t0, satp
    bnez    t0, test_fail

    # Test memory access in bare mode
    li      a0, 0xCAFEBABE
    la      a1, test_data
    sw      a0, 0(a1)
    lw      a2, 0(a1)
    bne     a0, a2, test_fail

    TEST_STAGE 7

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
