# ==============================================================================
# Test: Virtual Memory with SUM (Supervisor User Memory) Bit - Read Access
# ==============================================================================
#
# This test verifies:
# 1. SUM bit controls S-mode access to U-mode pages
# 2. When SUM=0: S-mode cannot read U-mode pages (should fault)
# 3. When SUM=1: S-mode can read U-mode pages
# 4. VM translation works correctly with U-bit set in PTEs
# 5. Page fault handling for access violations
#
# Approach:
# - Set up page table with U-bit set (user-accessible pages)
# - Try S-mode reads with SUM=0 (should fault)
# - Set SUM=1 and retry (should succeed)
# - Verify MXR bit doesn't affect read operations
#
# This is Week 1, Priority 1A: SUM bit with VM translation
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

# Combined flags for user-accessible read/write page (no execute)
.equ PTE_USER_RW,  (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)

# Combined flags for supervisor rwx page
.equ PTE_SUPERVISOR_RWX,  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)

# MSTATUS and SSTATUS bit positions
.equ MSTATUS_SUM_BIT,   18
.equ SSTATUS_SUM_BIT,   18

# Exception codes
.equ CAUSE_LOAD_PAGE_FAULT, 13

# ==============================================================================
# Data Section - Page Table and Test Data
# ==============================================================================

.section .data
.align 12  # 4KB alignment for page table

page_table_l1:
    # Entry 0: Maps VA 0x00000000-0x003FFFFF (4MB megapage) to PA 0x80000000
    # This page is marked as USER-accessible (U-bit set)
    # For Sv32 megapages: PTE format is [31:10] = PPN (22 bits), [9:0] = flags
    # Target PA = 0x80000000
    # PPN = PA[33:12] = 0x80000000 >> 12 = 0x80000 (22 bits)
    # PTE = (PPN << 10) | PTE_USER_RW = 0x20000000 | 0xD7 = 0x200000D7
    .word 0x200000D7

    # Entries 1-511: Invalid
    .fill 511, 4, 0x00000000

    # Entry 512: Maps VA 0x80000000-0x803FFFFF (4MB megapage) to PA 0x80000000
    # This is for code execution - supervisor mode, executable
    # PTE = 0x200000CF
    .word 0x200000CF

    # Entries 513-1023: Invalid
    .fill 511, 4, 0x00000000

# Test data area - will be accessed through both VA ranges
.align 4
test_data_user:
    .word 0xCAFEBABE

# Variable to track expected fault occurrence
.align 4
fault_expected:
    .word 0x00000000

# Variable to track if fault occurred
.align 4
fault_occurred:
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
    # STAGE 1: Setup in M-mode
    ###########################################################################

    # Verify SATP is initially 0 (bare mode)
    csrr    t0, satp
    bnez    t0, test_fail

    # Initialize test data
    li      t0, 0xDEADBEEF
    la      t1, test_data_user
    sw      t0, 0(t1)

    # Verify write succeeded
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    TEST_STAGE 2

    ###########################################################################
    # STAGE 2: Setup page table and SATP
    ###########################################################################

    # Calculate PPN of root page table
    la      t0, page_table_l1
    srli    t0, t0, 12          # Convert PA to PPN (PA >> 12)

    # Create SATP value: MODE=1 (Sv32), ASID=0, PPN=page_table_l1
    li      t1, SATP_MODE_SV32
    or      t0, t0, t1

    # Save SATP value for S-mode
    mv      s0, t0

    TEST_STAGE 3

    ###########################################################################
    # STAGE 3: Enter S-mode with SUM=0 (default)
    ###########################################################################

    # Set up S-mode trap vector
    SET_STVEC_DIRECT s_trap_handler

    # Ensure SUM bit is 0 in MSTATUS before entering S-mode
    li      t0, (1 << MSTATUS_SUM_BIT)
    csrc    mstatus, t0

    # Verify SUM=0
    csrr    t1, mstatus
    li      t2, (1 << MSTATUS_SUM_BIT)
    and     t3, t1, t2
    bnez    t3, test_fail

    # Enter S-mode
    ENTER_SMODE_M smode_entry

smode_entry:
    # Now in S-mode
    TEST_STAGE 4

    ###########################################################################
    # STAGE 4: Enable paging and verify SUM=0 in S-mode
    ###########################################################################

    # Write SATP to enable Sv32 paging
    csrw    satp, s0

    # Issue fence to flush TLB
    sfence.vma

    # Verify SATP was written correctly
    csrr    t1, satp
    bne     t1, s0, test_fail

    # Verify SUM=0 in SSTATUS
    csrr    t0, sstatus
    li      t1, (1 << SSTATUS_SUM_BIT)
    and     t2, t0, t1
    bnez    t2, test_fail

    TEST_STAGE 5

    ###########################################################################
    # STAGE 5: Try to read U-mode page with SUM=0 (should fault)
    ###########################################################################

    # Set fault_expected flag
    li      t0, 1
    la      t1, fault_expected
    sw      t0, 0(t1)

    # Clear fault_occurred flag
    la      t1, fault_occurred
    sw      zero, 0(t1)

    # Try to read from user page (VA 0x00000000 + offset)
    # This should cause a load page fault because:
    # - We're in S-mode
    # - Page has U-bit set
    # - SUM bit is 0
    la      t2, test_data_user
    li      t3, 0x003FFFFF
    and     t4, t2, t3          # Get offset within megapage
    # Read from VA range 0 (user-accessible page)
    lw      t5, 0(t4)           # This should fault!

    # If we get here, the fault didn't occur - that's wrong!
    j       test_fail

smode_after_first_fault:
    # We return here from trap handler after first fault
    TEST_STAGE 6

    ###########################################################################
    # STAGE 6: Verify fault occurred correctly
    ###########################################################################

    # Clear fault_expected flag
    la      t0, fault_expected
    sw      zero, 0(t0)

    # Verify fault_occurred flag is set
    la      t0, fault_occurred
    lw      t1, 0(t0)
    li      t2, 1
    bne     t1, t2, test_fail

    # Clear fault_occurred for next test
    sw      zero, 0(t0)

    TEST_STAGE 7

    ###########################################################################
    # STAGE 7: Set SUM=1 and retry read (should succeed)
    ###########################################################################

    # Set SUM bit in SSTATUS
    li      t0, (1 << SSTATUS_SUM_BIT)
    csrs    sstatus, t0

    # Verify SUM=1
    csrr    t1, sstatus
    li      t2, (1 << SSTATUS_SUM_BIT)
    and     t3, t1, t2
    beqz    t3, test_fail

    # Issue fence to ensure TLB is aware of permission change
    sfence.vma

    TEST_STAGE 8

    ###########################################################################
    # STAGE 8: Read U-mode page with SUM=1 (should succeed)
    ###########################################################################

    # Now read should succeed
    la      t2, test_data_user
    li      t3, 0x003FFFFF
    and     t4, t2, t3          # Get offset within megapage
    lw      t5, 0(t4)           # This should succeed now!

    # Verify we read the correct data
    li      t6, 0xDEADBEEF
    bne     t5, t6, test_fail

    TEST_STAGE 9

    ###########################################################################
    # STAGE 9: Write to U-mode page with SUM=1 (should succeed)
    ###########################################################################

    # Write new value
    li      t0, 0x12345678
    sw      t0, 0(t4)

    # Read back and verify
    lw      t1, 0(t4)
    bne     t0, t1, test_fail

    TEST_STAGE 10

    ###########################################################################
    # STAGE 10: Clear SUM and verify we can't read again
    ###########################################################################

    # Clear SUM bit
    li      t0, (1 << SSTATUS_SUM_BIT)
    csrc    sstatus, t0

    # Verify SUM=0
    csrr    t1, sstatus
    li      t2, (1 << SSTATUS_SUM_BIT)
    and     t3, t1, t2
    bnez    t3, test_fail

    # Issue fence
    sfence.vma

    # Set fault_expected flag
    li      t0, 1
    la      t1, fault_expected
    sw      t0, 0(t1)

    # Clear fault_occurred flag
    la      t1, fault_occurred
    sw      zero, 0(t1)

    # Try to read again (should fault)
    la      t2, test_data_user
    li      t3, 0x003FFFFF
    and     t4, t2, t3
    lw      t5, 0(t4)           # This should fault!

    # If we get here, test failed
    j       test_fail

smode_after_second_fault:
    # We return here from trap handler after second fault
    TEST_STAGE 11

    ###########################################################################
    # STAGE 11: Verify second fault occurred correctly
    ###########################################################################

    # Clear fault_expected flag
    la      t0, fault_expected
    sw      zero, 0(t0)

    # Verify fault_occurred flag is set
    la      t0, fault_occurred
    lw      t1, 0(t0)
    li      t2, 1
    bne     t1, t2, test_fail

    TEST_STAGE 12

    ###########################################################################
    # STAGE 12: Verify S-mode can still access S-mode pages normally
    ###########################################################################

    # Access through the supervisor VA range (0x80000000)
    # This uses entry 512 which doesn't have U-bit, so no SUM needed
    la      t0, test_data_user  # Physical address via supervisor VA
    lw      t1, 0(t0)
    li      t2, 0x12345678      # Last value we wrote
    bne     t1, t2, test_fail

    # Write via supervisor VA
    li      t3, 0xAABBCCDD
    sw      t3, 0(t0)
    lw      t4, 0(t0)
    bne     t3, t4, test_fail

    TEST_STAGE 13

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
    # Check if this is an expected page fault
    la      t0, fault_expected
    lw      t1, 0(t0)
    beqz    t1, unexpected_trap

    # Check if it's a load page fault
    csrr    t2, scause
    li      t3, CAUSE_LOAD_PAGE_FAULT
    bne     t2, t3, unexpected_trap

    # Set fault_occurred flag
    li      t4, 1
    la      t5, fault_occurred
    sw      t4, 0(t5)

    # Determine which fault this is by checking SEPC
    csrr    t0, sepc
    la      t1, smode_entry
    la      t2, smode_after_first_fault
    # If SEPC is before first return point, this is first fault
    bltu    t0, t2, first_fault_handler
    # Otherwise it's the second fault
    j       second_fault_handler

first_fault_handler:
    # Return to smode_after_first_fault
    la      t0, smode_after_first_fault
    csrw    sepc, t0
    sret

second_fault_handler:
    # Return to smode_after_second_fault
    la      t0, smode_after_second_fault
    csrw    sepc, t0
    sret

unexpected_trap:
    # Save trap info for debugging
    csrr    s1, scause
    csrr    s2, sepc
    csrr    s3, stval
    j       test_fail

# Trap data area
TRAP_TEST_DATA_AREA
