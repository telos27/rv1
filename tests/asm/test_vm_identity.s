# Test: Basic Virtual Memory with Identity Mapping
# Create a simple page table with identity mapping and enable paging
# This is for RV32 with Sv32 (2-level page table)

.section .data
.align 12  # Page align (4KB)

# Page table (Level 1 - Page Directory)
page_table_l1:
    # Entry 0: Maps VA 0x00000000-0x003FFFFF to PA 0x00000000-0x003FFFFF
    # PTE format: [31:10] = PPN, [9:0] = flags
    # Flags: V=1, R=1, W=1, X=1, U=0, G=0, A=1, D=1 = 0xCF
    .word 0x000000CF  # PPN=0, flags=0xCF (V|R|W|X|A|D)

    # Fill rest of page table with invalid entries
    .fill 1023, 4, 0x00000000

.section .text
.globl _start

_start:
    ###########################################################################
    # TEST 1: Verify we start in M-mode and can access memory
    ###########################################################################
    li      t0, 0x12345678
    la      t1, test_data
    sw      t0, 0(t1)
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    ###########################################################################
    # TEST 2: Setup SATP for Sv32 mode
    ###########################################################################
    # SATP format for Sv32:
    # [31] = MODE (1 for Sv32)
    # [30:22] = ASID (we'll use 0)
    # [21:0] = PPN of root page table

    # Get physical address of page table
    la      t0, page_table_l1
    srli    t0, t0, 12            # Convert to PPN (divide by 4096)

    # Set MODE = 1 (Sv32)
    li      t1, 0x80000000
    or      t0, t0, t1

    # Write to SATP
    csrw    satp, t0

    # Flush TLB
    sfence.vma

    ###########################################################################
    # TEST 3: Access memory with paging enabled (identity mapped)
    ###########################################################################
    li      t3, 0xABCDABCD
    la      t4, test_data
    sw      t3, 0(t4)
    lw      t5, 0(t4)
    bne     t3, t5, test_fail

    ###########################################################################
    # TEST 4: Disable paging and verify still works
    ###########################################################################
    # Set SATP.MODE = 0 (bare mode)
    csrw    satp, zero
    sfence.vma

    li      t6, 0xDEADC0DE
    la      s0, test_data
    sw      t6, 0(s0)
    lw      s1, 0(s0)
    bne     t6, s1, test_fail

    # SUCCESS
    j       test_pass

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    nop
    nop
    ebreak

# Test data location
.align 4
test_data:
    .word 0x00000000

.align 4
