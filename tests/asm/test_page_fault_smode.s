# Test: Page Fault in S-mode
# Page faults only occur in S-mode and U-mode, not M-mode!
# M-mode always uses physical addresses

.section .data
.align 12  # Page align (4KB)

# Page table
page_table:
    # Entry 0: Valid page (VA 0x00000000-0x003FFFFF)
    .word 0x000000CF  # PPN=0, V=1, R=1, W=1, X=1, A=1, D=1

    # Entry 1: INVALID page (VA 0x00400000-0x007FFFFF)
    .word 0x00000000  # V=0 (invalid) - should cause page fault

    # Fill rest
    .fill 1022, 4, 0x00000000

.section .text
.globl _start

_start:
    ###########################################################################
    # Setup trap handlers (M-mode and S-mode)
    ###########################################################################
    la      t0, m_trap_handler
    csrw    mtvec, t0

    la      t0, s_trap_handler
    csrw    stvec, t0

    # Delegate page faults to S-mode
    li      t0, 0x0000E000        # Bits 13 and 15 (load and store page faults)
    csrw    medeleg, t0

    ###########################################################################
    # Enable paging
    ###########################################################################
    la      t0, page_table
    srli    t0, t0, 12
    li      t1, 0x80000000
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    ###########################################################################
    # Enter S-mode
    ###########################################################################
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF
    and     t0, t0, t1
    li      t1, 0x00000800
    or      t0, t0, t1
    csrw    mstatus, t0

    la      t0, s_mode_code
    csrw    mepc, t0
    mret

s_mode_code:
    ###########################################################################
    # Now in S-mode with paging enabled
    # TEST: Access invalid page (should cause page fault to S-mode)
    ###########################################################################
    li      s0, 0x00400000      # Invalid page
    lw      s1, 0(s0)           # Should fault to S-mode handler

    # Should NOT reach here
    j       test_fail

s_trap_handler:
    # S-mode trap handler
    # Check for load page fault (cause = 13)
    csrr    s2, scause
    li      s3, 13
    bne     s2, s3, test_fail

    # SUCCESS!
    j       test_pass

m_trap_handler:
    # M-mode trap handler (should not be used if delegation works)
    j       test_fail

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
