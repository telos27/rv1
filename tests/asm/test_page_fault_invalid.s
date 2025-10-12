# Test: Page Fault - Invalid Page (V=0)
# Test that accessing a page with V=0 causes a page fault

.section .data
.align 12  # Page align (4KB)

# Page table with valid and invalid entries
page_table:
    # Entry 0: Valid page (VA 0x00000000-0x003FFFFF)
    .word 0x000000CF  # PPN=0, V=1, R=1, W=1, X=1, A=1, D=1

    # Entry 1: INVALID page (VA 0x00400000-0x007FFFFF)
    .word 0x00000000  # V=0 (invalid)

    # Fill rest
    .fill 1022, 4, 0x00000000

.section .text
.globl _start

_start:
    ###########################################################################
    # Setup trap handler to catch page faults
    ###########################################################################
    la      t0, trap_handler
    csrw    mtvec, t0

    ###########################################################################
    # Enable paging with Sv32
    ###########################################################################
    la      t0, page_table
    srli    t0, t0, 12
    li      t1, 0x80000000
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    ###########################################################################
    # TEST 1: Access valid page (should work)
    ###########################################################################
    li      t1, 0xAAAAAAAA
    li      t2, 0x00000100      # Address in first page (valid)
    sw      t1, 0(t2)
    lw      t3, 0(t2)
    bne     t1, t3, test_fail

    ###########################################################################
    # TEST 2: Access invalid page (should cause page fault)
    ###########################################################################
    # This should trigger load page fault (cause = 13)
    li      s0, 0x00400000      # Address in second page (invalid, V=0)
    lw      s1, 0(s0)           # This should fault!

    # Should NOT reach here
    j       test_fail

trap_handler:
    # Check if we got a page fault
    csrr    t4, mcause

    # Check for load page fault (cause = 13)
    li      t5, 13
    bne     t4, t5, test_fail

    # Check mtval contains faulting address
    csrr    t6, mtval
    # Note: mtval might be 0 if not implemented
    # For now, just check we got the right exception cause

    # SUCCESS - We caught the page fault!
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

.align 4
