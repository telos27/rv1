# ==============================================================================
# Test: Page Fault Recovery - Invalid Page
# ==============================================================================
#
# This test verifies that page faults can be recovered by fixing the PTE
# and retrying the faulting instruction. This is a critical OS feature for:
# - Demand paging (allocate pages on first access)
# - Copy-on-write (mark pages read-only, allocate on write  
# - Swap (bring pages back from disk)
#
# Test Sequence:
# 1. Setup page table with INVALID page (V=0)  
# 2. Enter S-mode
# 3. Setup trap handler  
# 4. Try to access invalid page → triggers load page fault
# 5. Trap handler fixes PTE (sets V=1)
# 6. Trap handler executes SFENCE.VMA
# 7. Trap handler returns to retry instruction (SEPC unchanged)
# 8. Load succeeds on retry
# 9. Verify data is correct
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
    # Setup M-mode trap handler first (for unexpected traps)
    ###########################################################################
    
    SET_MTVEC_DIRECT m_trap_handler

    TEST_STAGE 2

    ###########################################################################
    # Setup page table with identity megapage (like test_tlb_basic_hit_miss)
    ###########################################################################

    la      t1, page_table_l1

    # L1 entry 512: Identity megapage for code/data region
    # VA 0x80000000-0x803FFFFF → PA 0x80000000-0x803FFFFF
    li      t0, 0x200000CF          # Megapage: V|R|W|X|A|D
    li      t2, 2048                # Offset for L1[512]
    add     t2, t1, t2              # Calculate address of L1[512]
    sw      t0, 0(t2)               # Store megapage PTE

    TEST_STAGE 3

    ###########################################################################
    # Setup test data in physical memory BEFORE enabling paging
    ###########################################################################

    li      t0, 0x12345678          # Test value
    la      t1, test_data
    sw      t0, 0(t1)               # Write to physical address

    TEST_STAGE 4

    ###########################################################################
    # Mark test_data page as INVALID in page table
    # We'll set it up so when accessed, it causes page fault
    # Then trap handler will fix it
    ###########################################################################

    # Get L1 entry index for test_data VA (0x80005xxx is in megapage 512)
    # Actually, let's create a L0 page table for finer control
    
    # L1 entry 0: Points to L0 page table for VA 0x00000000-0x003FFFFF
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table pointer

    # L0 entry for VA 0x00010000: Map to test_data but mark INVALID
    la      t0, test_data
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0xD6            # R|W|U|A|D but V=0 (INVALID!)
    la      t1, page_table_l0
    sw      t0, 64(t1)              # L0[16] for VA 0x00010000

    TEST_STAGE 5

    ###########################################################################
    # Enable paging
    ###########################################################################

    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN
    li      t1, 0x80000000          # MODE = Sv32
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    TEST_STAGE 6

    ###########################################################################
    # Delegate page faults to S-mode and setup trap handler
    ###########################################################################

    # Delegate load page fault to S-mode (so S-mode handler gets it, not M-mode)
    DELEGATE_EXCEPTION CAUSE_LOAD_PAGE_FAULT

    # Setup S-mode trap handler BEFORE entering S-mode
    SET_STVEC_DIRECT s_trap_handler

    TEST_STAGE 7

    ###########################################################################
    # Enter S-mode
    ###########################################################################

    ENTER_SMODE_M smode_entry

smode_entry:
    TEST_STAGE 8

    # Initialize fault counter
    la      t0, fault_count
    sw      zero, 0(t0)

    TEST_STAGE 9

    ###########################################################################
    # Try to access invalid page - should fault, handler fixes, then succeeds
    ###########################################################################

    li      t0, 0x00010000          # VA of invalid page
    lw      t1, 0(t0)               # Load → PAGE FAULT → Handler fixes → Retry → Success

    TEST_STAGE 10

    ###########################################################################
    # Verify loaded value matches what we wrote
    ###########################################################################

    li      t2, 0x12345678
    bne     t1, t2, test_fail

    TEST_STAGE 11

    ###########################################################################
    # Verify we only faulted once
    ###########################################################################

    la      t0, fault_count
    lw      t1, 0(t0)
    li      t2, 1
    bne     t1, t2, test_fail       # Should have faulted exactly once

    # Test passed!
    j       test_pass

###############################################################################
# S-mode trap handler - Fixes invalid page
###############################################################################

s_trap_handler:
    # Check exception cause
    csrr    t0, scause
    li      t1, CAUSE_LOAD_PAGE_FAULT
    bne     t0, t1, s_trap_fail

    # Verify faulting address
    csrr    t0, stval
    li      t1, 0x00010000
    bne     t0, t1, s_trap_fail

    # Increment fault counter
    la      t0, fault_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)

    # Check not too many faults (would indicate fix didn't work)
    li      t2, 2
    bge     t1, t2, s_trap_fail

    # Fix the PTE: Set V=1
    la      t0, page_table_l0
    lw      t1, 64(t0)              # Read PTE for VA 0x00010000
    ori     t1, t1, 0x01            # Set V=1
    sw      t1, 64(t0)              # Write back

    # Flush TLB
    sfence.vma

    # Return to retry instruction (don't modify SEPC)
    sret

s_trap_fail:
    TEST_STAGE 0xF0
    j       test_fail

###############################################################################
# M-mode trap handler (unexpected traps)
###############################################################################

m_trap_handler:
    # Save mcause/mtval to s registers for debugging (TEST_STAGE uses t4)
    csrr    s0, mcause
    csrr    s1, mtval
    TEST_STAGE 0xFF
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

.align 12
page_table_l1:
    .space 4096

.align 12
page_table_l0:
    .space 4096

.align 12
test_data:
    .word 0x00000000
    .space 4092

.align 4
fault_count:
    .word 0
