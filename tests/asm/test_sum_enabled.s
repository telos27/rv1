# test_sum_enabled.s - Test SUM bit enabled (S-mode can access U-pages)
#
# Test Description:
# - Set MSTATUS.SUM = 1 (Supervisor User Memory access enabled)
# - Enter S-mode
# - Access U-mode pages (PTE.U = 1)
# - Expected: Access succeeds (SUM=1 allows S-mode to access U-pages)
#
# This is the complement of test_sum_disabled.s and critical for xv6
# where kernel needs to access user memory during syscalls.

.section .text
.globl _start

_start:
    # Initialize test state
    li t0, 1
    li gp, 0                    # gp=0 means test not passed yet

    #==========================================================================
    # Stage 1: Setup - Create page table with U-page
    #==========================================================================

    # Create 1-level page table for Sv32 (identity mapping + U-page)
    # L1 page table at 0x80001000
    la t1, page_table_l1

    # Entry 512: Identity map for kernel code (VA 0x80000000 → PA 0x80000000)
    # PPN = 0x80000 (for PA 0x80000000), permissions: V=1, R=1, W=1, X=1, U=0 (S-mode page)
    li t2, 0x200000CF           # PPN[21:10]=0x80000, flags=0xCF (V,R,W,X)
    li t4, 2048
    add t4, t1, t4
    sw t2, 0(t4)                # page_table[512] = 0x200000CF

    # Entry 0: Identity map VA 0x00000000-0x003FFFFF as U-mode megapage
    # This creates a 4MB megapage at VA 0 → PA 0 (identity)
    # PPN = 0 (for PA 0x00000000), permissions: V=1, R=1, W=1, X=0, U=1
    li t2, 0x000000D7           # PPN=0, flags=0xD7 (V,R,W,U, no X)
    sw t2, 0(t1)                # page_table[0] = 0x000000D7

    # Entry 513: Also identity map VA 0x80400000 as S-mode page for extended code/data
    # PPN = 0x80400 >> 2 = 0x20100 (for PA 0x80400000)
    li t2, 0x204000CF           # PPN=0x20100, flags=0xCF (V,R,W,X, no U)
    li t4, 2052                 # Entry 513 offset
    add t4, t1, t4
    sw t2, 0(t4)                # page_table[513] = 0x204000CF

    #==========================================================================
    # Stage 2: Enable paging with SUM=1
    #==========================================================================

    # Setup SATP for Sv32: MODE=1 (bit 31), PPN=page_table_l1
    la t1, page_table_l1
    srli t1, t1, 12             # PPN = PA >> 12
    li t2, 0x80000000           # MODE = 1 (Sv32)
    or t1, t1, t2

    # Set MSTATUS.SUM = 1 (bit 18)
    # Also set MSTATUS.MPRV = 0 (we'll use real S-mode, not MPRV)
    li t2, 0x00040000           # SUM bit (bit 18)
    csrs mstatus, t2            # Set SUM=1

    # Verify SUM is set
    csrr t3, mstatus
    li t4, 0x00040000
    and t3, t3, t4
    beqz t3, test_fail          # If SUM not set, fail

    # Setup delegation: delegate page faults to S-mode
    # (Not strictly necessary for this test since we expect no faults)
    li t2, 0x0000B000           # Bits 13,15 (load/store page fault)
    csrw medeleg, t2

    # Setup STVEC (S-mode trap vector)
    la t2, s_trap_handler
    csrw stvec, t2

    # Enable SATP (this enables paging)
    csrw satp, t1
    sfence.vma                  # Flush TLB

    #==========================================================================
    # Stage 3: Enter S-mode
    #==========================================================================

    # Setup MEPC to s_mode_entry
    la t1, s_mode_entry
    csrw mepc, t1

    # Setup MSTATUS for MRET:
    # - MPP = 01 (S-mode)
    # - MPIE = 1 (enable interrupts after MRET)
    # - Preserve SUM=1
    li t1, 0x00001800           # MPP = 01
    li t2, 0x00000080           # MPIE = 1
    or t1, t1, t2
    li t2, 0x00040000           # SUM = 1
    or t1, t1, t2

    csrr t2, mstatus
    li t3, 0xFFFFE777           # Clear MPP, MPIE fields
    and t2, t2, t3
    or t2, t2, t1
    csrw mstatus, t2

    # Enter S-mode via MRET
    mret

    #==========================================================================
    # S-mode code - Test SUM=1 allows access to U-pages
    #==========================================================================
s_mode_entry:
    # Verify we're in S-mode (check privilege in CSR)
    # Read MSTATUS, current privilege should be 01 (S-mode)
    # Note: Privilege is not directly readable, but we can infer from behavior

    # Test 1: Write to U-page through VA 0x00002000
    # VA 0x00002000 maps through entry 0 (VA 0x00000000-0x003FFFFF) as U-page
    li t5, 0xDEADBEEF
    li t6, 0x00002000           # VA = 0x00002000 (identity mapped as U-page)
    sw t5, 0(t6)                # Store to U-page - should SUCCEED with SUM=1

    # Test 2: Read back from U-page
    lw a0, 0(t6)
    bne t5, a0, test_fail       # If value doesn't match, fail

    # Test 3: Write different value to offset +4
    li t5, 0xCAFEBABE
    sw t5, 4(t6)
    lw a0, 4(t6)
    bne t5, a0, test_fail

    # Test 4: Access at offset +8
    li t5, 0x12345678
    sw t5, 8(t6)
    lw a0, 8(t6)
    bne t5, a0, test_fail

    # Test 5: Verify SUM is still enabled (read MSTATUS via CSRRS)
    # Note: S-mode can't read MSTATUS directly, but SSTATUS shows subset
    csrr t3, sstatus
    # SUM bit in SSTATUS is bit 18 (same as MSTATUS)
    li t4, 0x00040000
    and t3, t3, t4
    beqz t3, test_fail          # If SUM cleared somehow, fail

    #==========================================================================
    # All tests passed!
    #==========================================================================
test_pass:
    li gp, 1                    # gp=1 signals success
    j end_test

test_fail:
    li gp, 0                    # gp=0 signals failure
    j end_test

    #==========================================================================
    # S-mode trap handler (should not be reached)
    #==========================================================================
s_trap_handler:
    # If we trapped, something went wrong (SUM=1 should allow access)
    li gp, 0
    j end_test

end_test:
    # Write to test marker address to signal completion
    li t0, 0x80002100
    sw gp, 0(t0)

    # Infinite loop
1:  j 1b

#==============================================================================
# Data Section
#==============================================================================
.section .data
.align 12                       # Align to 4KB for page table

page_table_l1:
    .space 4096                 # 1024 entries * 4 bytes

.align 4
test_data_area:
    .word 0x00000000            # Test data location
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000
