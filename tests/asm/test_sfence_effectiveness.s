# test_sfence_effectiveness.s - Test SFENCE.VMA TLB invalidation
#
# Test Description:
# - Setup translation with specific PTE
# - Access page to load TLB
# - Modify PTE (change permissions or PPN)
# - Access WITHOUT sfence → should see stale TLB data
# - Execute SFENCE.VMA
# - Access WITH sfence → should see new PTE data
#
# This verifies that SFENCE.VMA properly invalidates TLB entries.

.section .text
.globl _start

_start:
    li gp, 0                    # gp=0 means test not passed

    #==========================================================================
    # Stage 1: Setup page table
    #==========================================================================

    la t1, page_table_l1

    # Entry 512: Identity map kernel (VA 0x80000000 → PA 0x80000000)
    li t2, 0x200000CF
    li t3, 2048
    add t3, t1, t3
    sw t2, 0(t3)

    # Entry 0: Map VA 0x00002000 → PA test_data_area
    # Initial mapping with specific data
    la t4, test_data_area
    srli t2, t4, 12
    slli t2, t2, 10
    ori t2, t2, 0xD7            # V=1, R=1, W=1, X=0, U=1
    sw t2, 0(t1)

    # Save page table address for later modification
    la t3, saved_pt_addr
    sw t1, 0(t3)

    #==========================================================================
    # Stage 2: Enable paging
    #==========================================================================

    srli t1, t1, 12
    li t2, 0x80000000
    or t1, t1, t2
    csrw satp, t1
    sfence.vma

    #==========================================================================
    # Stage 3: Enter S-mode
    #==========================================================================

    la t1, s_mode_entry
    csrw mepc, t1

    li t1, 0x00041880           # MPP=01, MPIE=1, SUM=1
    csrr t2, mstatus
    li t3, 0xFFFFE777
    and t2, t2, t3
    or t2, t2, t1
    csrw mstatus, t2

    mret

s_mode_entry:
    #==========================================================================
    # Test 1: Load TLB with initial mapping
    #==========================================================================

    # Write test pattern to VA 0x00002000
    li t5, 0x00002000
    li t0, 0x11111111
    sw t0, 0(t5)

    # Read back to confirm and load TLB
    lw t1, 0(t5)
    bne t0, t1, test_fail

    #==========================================================================
    # Test 2: Modify PTE WITHOUT sfence (TLB should be stale)
    #==========================================================================

    # Map VA 0x00002000 to alternate_data instead
    la t2, saved_pt_addr
    lw t2, 0(t2)                # Get page table address

    la t4, alternate_data       # New target PA
    srli t3, t4, 12
    slli t3, t3, 10
    ori t3, t3, 0xD7            # Same permissions, different PPN
    sw t3, 0(t2)                # Update PTE

    # Write different pattern to alternate_data (via PA, not VA)
    la t4, alternate_data
    li t0, 0x22222222
    sw t0, 0(t4)                # Write to PA directly

    # Try to read from VA 0x00002000 WITHOUT sfence
    # Should still hit TLB and get OLD mapping (test_data_area with 0x11111111)
    lw t1, 0(t5)
    li t0, 0x11111111           # Expect STALE data
    bne t0, t1, test_fail       # If we got new data, TLB wasn't used (fail)

    #==========================================================================
    # Test 3: Execute SFENCE.VMA and verify new mapping
    #==========================================================================

    sfence.vma                  # Invalidate TLB

    # Now read from VA 0x00002000 again
    # Should use NEW mapping (alternate_data with 0x22222222)
    lw t1, 0(t5)
    li t0, 0x22222222           # Expect NEW data
    bne t0, t1, test_fail

    # Write to VA and verify it goes to alternate_data
    li t0, 0x33333333
    sw t0, 0(t5)                # Write via VA

    # Read directly from alternate_data PA
    la t4, alternate_data
    lw t1, 0(t4)
    li t0, 0x33333333
    bne t0, t1, test_fail

    j test_pass

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

#==============================================================================
# Data Section
#==============================================================================
.section .data
.align 12

page_table_l1:
    .space 4096

.align 4
test_data_area:
    .word 0x00000000
    .word 0x00000000

alternate_data:
    .word 0x00000000
    .word 0x00000000

saved_pt_addr:
    .word 0x00000000
