# test_page_fault_invalid_recover.s - Test page fault recovery and retry
#
# Test Description:
# - Setup page table with invalid PTE (V=0)
# - Access invalid page → triggers page fault
# - Trap handler fixes PTE (sets V=1)
# - Handler executes SFENCE.VMA to flush TLB
# - Handler returns via SRET (retry faulting instruction)
# - Second attempt succeeds
#
# This tests the critical OS capability for demand paging where pages
# are initially marked invalid and loaded on-demand when accessed.

.section .text
.globl _start

_start:
    # Initialize test state
    li gp, 0                    # gp=0 means test not passed yet

    #==========================================================================
    # Stage 1: Setup page table with ONE invalid entry
    #==========================================================================

    # Create 1-level page table for Sv32
    la t1, page_table_l1

    # Entry 512: Identity map for kernel code (VA 0x80000000 → PA 0x80000000)
    # Valid, S-mode accessible
    li t2, 0x200000CF           # PPN=0x80000, flags=0xCF (V,R,W,X)
    li t3, 2048
    add t3, t1, t3
    sw t2, 0(t3)                # page_table[512] = 0x200000CF

    # Entry 0: Map VA 0x00002000 with INVALID PTE initially (V=0)
    # This will cause a page fault on first access
    # We'll point to test_data_area but mark V=0
    la t4, test_data_area
    srli t2, t4, 12             # PPN = PA >> 12
    slli t2, t2, 10             # Shift to PTE format
    ori t2, t2, 0xD6            # V=0(!), R=1, W=1, X=0, U=1 (invalid user page)
    sw t2, 0(t1)                # page_table[0] = PPN | 0xD6 (INVALID!)

    # Save the invalid PTE value for trap handler to fix
    la t3, saved_invalid_pte
    sw t2, 0(t3)

    #==========================================================================
    # Stage 2: Enable paging
    #==========================================================================

    # Setup SATP for Sv32
    srli t1, t1, 12             # PPN
    li t2, 0x80000000           # MODE = 1
    or t1, t1, t2

    # Setup trap delegation: delegate page faults to S-mode
    li t2, 0x0000F000           # Bits 12,13,15 (instruction/load/store page fault)
    csrw medeleg, t2

    # Setup STVEC (S-mode trap vector)
    la t2, s_trap_handler
    csrw stvec, t2

    # Enable SATP (enable paging)
    csrw satp, t1
    sfence.vma

    #==========================================================================
    # Stage 3: Enter S-mode
    #==========================================================================

    la t1, s_mode_entry
    csrw mepc, t1

    # Setup MSTATUS: MPP=01 (S-mode), MPIE=1, SUM=1
    li t1, 0x00041880           # MPP=01, MPIE=1, SUM=1
    csrr t2, mstatus
    li t3, 0xFFFFE777
    and t2, t2, t3
    or t2, t2, t1
    csrw mstatus, t2

    mret

    #==========================================================================
    # S-mode code - Attempt to access invalid page
    #==========================================================================
s_mode_entry:
    # Attempt 1: Load from VA 0x00002000 (invalid PTE, V=0)
    # This WILL page fault and trap to s_trap_handler
    li t5, 0x00002000
    lw t6, 0(t5)                # ← PAGE FAULT HERE (first time)

    # If we reach here, the page fault was handled and we retried successfully!
    # The trap handler fixed the PTE and we retried the load

    # Verify the data we loaded
    li t0, 0xDEADBEEF           # Expected value (written by trap handler)
    bne t6, t0, test_fail

    # Attempt 2: Try writing to the same page (should work now)
    li t0, 0xCAFEBABE
    sw t0, 4(t5)
    lw t1, 4(t5)
    bne t0, t1, test_fail

    # Success!
    j test_pass

    #==========================================================================
    # S-mode trap handler - Fix invalid PTE and retry
    #==========================================================================
s_trap_handler:
    # Check SCAUSE to verify it's a page fault
    csrr t0, scause
    li t1, 13                   # Load page fault
    bne t0, t1, test_fail       # If not load page fault, fail

    # Check STVAL contains the faulting address
    csrr t0, stval
    li t1, 0x00002000
    bne t0, t1, test_fail       # If wrong address, fail

    # Fix the PTE: Set V=1 to make it valid
    la t1, page_table_l1
    la t2, saved_invalid_pte
    lw t2, 0(t2)                # Load saved PTE
    ori t2, t2, 0x01            # Set V=1
    sw t2, 0(t1)                # Update page_table[0]

    # Write test data to the page (before marking valid, direct PA access)
    # Actually, we just marked it valid, so we can access via VA now
    li t0, 0xDEADBEEF
    li t3, 0x00002000
    sw t0, 0(t3)                # Write through VA (now valid)

    # CRITICAL: Flush TLB to ensure updated PTE is used
    sfence.vma

    # Return from trap (retry the faulting instruction)
    # SEPC already points to the faulting load instruction
    sret                        # Retry the load

test_pass:
    li gp, 1                    # Success
    j end_test

test_fail:
    li gp, 0                    # Failure
    j end_test

end_test:
    # Write to test marker
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
    .word 0x00000000
    .word 0x00000000

saved_invalid_pte:
    .word 0x00000000            # Store invalid PTE here for handler
