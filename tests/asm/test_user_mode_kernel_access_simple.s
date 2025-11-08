# test_user_mode_kernel_access_simple.s
# Simplified test to debug permission violations
#
# Just tests: U-mode cannot read kernel page (U=0)

.section .text
.globl _start

_start:
    # Initialize stack pointer
    la sp, stack_top

    # Enter S-mode from M-mode
    li t0, 0x00000800        # MPP=01 (S-mode)
    csrw mstatus, t0
    la t0, s_mode_entry
    csrw mepc, t0
    li t0, 0xFFFFFFFF
    csrw medeleg, t0
    mret

s_mode_entry:
    # Setup page tables
    call setup_page_tables

    # Enable Sv32 paging
    la t0, page_table
    srli t0, t0, 12
    li t1, 0x80000000
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    # Setup trap handler
    la t0, trap_handler
    csrw stvec, t0

    # Initialize fault flag
    la t0, got_page_fault
    sw zero, 0(t0)

    # Copy user code to user_code_page (VA 0x30000000, U=1)
    # This allows U-mode to execute it
    la t0, user_code_template
    li t1, 0x30000000
    li t2, 32                # Copy 32 bytes
1:
    lw t3, 0(t0)
    sw t3, 0(t1)
    addi t0, t0, 4
    addi t1, t1, 4
    addi t2, t2, -4
    bnez t2, 1b

    # Enter U-mode, jumping to user code at VA 0x30000000
    li t0, 0x00000020        # SPIE bit
    csrw sstatus, t0
    li t0, 0x30000000
    csrw sepc, t0
    sret

# Template for user code (will be copied to U=1 page)
user_code_template:
    # U-mode: Try to read kernel page (should fault)
    li t0, 0x10000000
    lw t1, 0(t0)             # Should trigger load page fault
    # If we get here, no fault occurred - test failed!
    li gp, 0
    li t0, 0x80002100
    sw gp, 0(t0)
1:  j 1b

after_fault:
    # Check that we got the fault
    la t0, got_page_fault
    lw t1, 0(t0)
    li t2, 1
    bne t1, t2, test_fail

    # Test passed!
    j test_pass

# Trap handler
trap_handler:
    csrr t0, scause
    li t1, 13                # Load page fault
    bne t0, t1, test_fail

    # Verify faulting address
    csrr t0, stval
    li t1, 0x10000000
    bne t0, t1, test_fail

    # Set flag
    la t0, got_page_fault
    li t1, 1
    sw t1, 0(t0)

    # Return to after_fault in S-mode
    la t0, after_fault
    csrw sepc, t0

    # Set SPP=1 (S-mode) in sstatus
    csrr t0, sstatus
    li t1, 0x00000100        # SPP bit
    or t0, t0, t1
    csrw sstatus, t0

    sret

# Setup page tables
setup_page_tables:
    # Clear page table
    la t0, page_table
    li t1, 0
    li t2, 1024
1:
    sw t1, 0(t0)
    addi t0, t0, 4
    addi t2, t2, -1
    bnez t2, 1b

    # Entry 512: Code region megapage (VA 0x80000000)
    # V=1, R=1, W=1, X=1, U=0 for S-mode code/data access
    la t0, page_table
    li t1, 512
    slli t1, t1, 2
    add t0, t0, t1
    li t1, 0x80000
    slli t1, t1, 10
    ori t1, t1, 0x0F         # V=1, R=1, W=1, X=1, U=0 (kernel megapage)
    sw t1, 0(t0)

    # Entry 64: Kernel page (VA 0x10000000)
    # Points to L1 page table
    la t0, page_table
    li t1, 64
    slli t1, t1, 2
    add t0, t0, t1
    la t1, l1_kernel_pt
    srli t1, t1, 2
    slli t1, t1, 10
    ori t1, t1, 0x01         # V=1 (pointer)
    sw t1, 0(t0)

    # L1 entry 0: Map VA 0x10000000 to kernel_data
    # V=1, R=1, W=1, U=0 (KERNEL ONLY!)
    la t0, l1_kernel_pt
    la t1, kernel_data
    srli t1, t1, 2
    slli t1, t1, 10
    ori t1, t1, 0x0F         # V=1, R=1, W=1, U=0
    sw t1, 0(t0)

    # Entry 192: User code page (VA 0x30000000)
    # Points to L1 page table for user pages
    la t0, page_table
    li t1, 192
    slli t1, t1, 2
    add t0, t0, t1
    la t1, l1_user_pt
    srli t1, t1, 2
    slli t1, t1, 10
    ori t1, t1, 0x01         # V=1 (pointer)
    sw t1, 0(t0)

    # L1 entry 0: Map VA 0x30000000 to user_code_page
    # V=1, R=1, W=1, X=1, U=1 (USER accessible, executable)
    la t0, l1_user_pt
    la t1, user_code_page
    srli t1, t1, 2
    slli t1, t1, 10
    ori t1, t1, 0x1F         # V=1, R=1, W=1, X=1, U=1
    sw t1, 0(t0)

    ret

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

.section .data
.align 12

page_table:
    .skip 4096

l1_kernel_pt:
    .skip 4096

l1_user_pt:
    .skip 4096

.align 12
kernel_data:
    .skip 4096

.align 12
user_code_page:
    .skip 4096

.align 4
got_page_fault:
    .word 0

.align 12
stack_space:
    .skip 4096
stack_top:
