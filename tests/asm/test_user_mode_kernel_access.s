# test_user_mode_kernel_access.s
# Phase 4 Week 2: Permission Violation Test
# Tests that U-mode cannot access kernel memory pages (U=0)
#
# Test Strategy:
# 1. Set up page tables with kernel page (U=0) and user page (U=1)
# 2. Enter U-mode
# 3. Try to read from kernel page → expect load page fault (code 13)
# 4. Try to write to kernel page → expect store page fault (code 15)
# 5. Verify user page access still works
# 6. Return to S-mode and verify kernel page access works
#
# Expected behavior:
# - U-mode reading kernel page: Load page fault (scause=13)
# - U-mode writing kernel page: Store page fault (scause=15)
# - U-mode accessing user page: Success
# - S-mode accessing kernel page: Success

.section .text
.globl _start

_start:
    # Initialize stack pointer
    la sp, stack_top

    # First, enter S-mode from M-mode
    # Set MPP=01 (S-mode) in mstatus
    li t0, 0x00000800        # MPP=01 (S-mode)
    csrw mstatus, t0

    # Set MEPC to s_mode_entry
    la t0, s_mode_entry
    csrw mepc, t0

    # Setup M-mode trap delegation
    # Delegate all exceptions to S-mode (all bits set)
    li t0, 0xFFFFFFFF
    csrw medeleg, t0

    # Jump to S-mode
    mret

s_mode_entry:
    # Now in S-mode
    # Setup page tables with kernel and user pages
    call setup_page_tables

    # Enable Sv32 paging (satp.MODE = 1, PPN = page_table base)
    la t0, page_table
    srli t0, t0, 12          # Get PPN
    li t1, 0x80000000        # Sv32 mode bit
    or t0, t0, t1
    csrw satp, t0
    sfence.vma               # Flush TLB

    # Setup trap handler for page faults
    la t0, trap_handler
    csrw stvec, t0

    # Initialize page fault counters
    la t0, load_fault_count
    sw zero, 0(t0)
    la t0, store_fault_count
    sw zero, 0(t0)

    # Enter U-mode from S-mode
    # Set SPP=0 (return to U-mode), SPIE=1 (enable interrupts)
    li t0, 0x00000020        # SPIE bit
    csrw sstatus, t0

    # Set SEPC to user_code
    la t0, user_code
    csrw sepc, t0

    # Jump to U-mode
    sret

user_code:
    # U-mode - try to read kernel page (should fault)
    # Try to load from kernel page (VA 0x10000000)
    li t0, 0x10000000
    lw t1, 0(t0)             # Should trigger load page fault

    # Should not reach here - if we do, test failed
    j test_fail

after_load_fault:
    # U-mode - try to write kernel page (should fault)
    # Try to store to kernel page (VA 0x10000000)
    li t0, 0x10000000
    li t1, 0x12345678
    sw t1, 0(t0)             # Should trigger store page fault

    # Should not reach here
    j test_fail

after_store_fault:
    # U-mode - verify user page access works
    # Access user page (VA 0x20000000, U=1)
    li t0, 0x20000000
    li t1, 0xCAFEBABE
    sw t1, 0(t0)             # Should succeed
    lw t2, 0(t0)             # Should succeed

    # Verify data matches
    bne t1, t2, test_fail

    # Return to S-mode
    # Use ECALL to return to S-mode
    ecall

back_in_smode:
    # S-mode - verify kernel page access works
    # Access kernel page (VA 0x10000000, U=0)
    li t0, 0x10000000
    li t1, 0xDEADBEEF
    sw t1, 0(t0)             # Should succeed in S-mode
    lw t2, 0(t0)             # Should succeed in S-mode

    # Verify data matches
    bne t1, t2, test_fail

    # Verify fault counts
    # Check that we got exactly 1 load fault and 1 store fault
    la t0, load_fault_count
    lw t1, 0(t0)
    li t2, 1
    bne t1, t2, test_fail

    la t0, store_fault_count
    lw t1, 0(t0)
    li t2, 1
    bne t1, t2, test_fail

    # All tests passed!
    j test_pass

# Trap handler
trap_handler:
    # Save context
    csrw sscratch, sp
    la sp, trap_stack_top
    addi sp, sp, -128
    sw ra, 0(sp)
    sw t0, 4(sp)
    sw t1, 8(sp)
    sw t2, 12(sp)
    sw a0, 16(sp)

    # Check cause
    csrr t0, scause
    li t1, 13                # Load page fault
    beq t0, t1, handle_load_fault

    li t1, 15                # Store page fault
    beq t0, t1, handle_store_fault

    li t1, 8                 # ECALL from U-mode
    beq t0, t1, handle_ecall

    # Unexpected trap
    j test_fail

handle_load_fault:
    # Increment load fault counter
    la t0, load_fault_count
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)

    # Check that we faulted on correct address
    csrr t0, stval
    li t1, 0x10000000
    bne t0, t1, test_fail

    # Return to after_load_fault
    la t0, after_load_fault
    csrw sepc, t0
    j trap_return

handle_store_fault:
    # Increment store fault counter
    la t0, store_fault_count
    lw t1, 0(t0)
    addi t1, t1, 1
    sw t1, 0(t0)

    # Check that we faulted on correct address
    csrr t0, stval
    li t1, 0x10000000
    bne t0, t1, test_fail

    # Return to after_store_fault
    la t0, after_store_fault
    csrw sepc, t0
    j trap_return

handle_ecall:
    # ECALL from U-mode - return to S-mode
    # Set SEPC to back_in_smode
    la t0, back_in_smode
    csrw sepc, t0

    # Set SPP=1 (S-mode)
    csrr t0, sstatus
    li t1, 0x00000100        # SPP bit
    or t0, t0, t1
    csrw sstatus, t0
    j trap_return

trap_return:
    # Restore context
    lw ra, 0(sp)
    lw t0, 4(sp)
    lw t1, 8(sp)
    lw t2, 12(sp)
    lw a0, 16(sp)
    addi sp, sp, 128
    csrr sp, sscratch
    sret

# Setup page tables
setup_page_tables:
    # Page table layout:
    # - Code region (0x80000000): Identity megapage (U=1 for this test)
    # - Kernel page (0x10000000): 4KB page mapping to kernel_data (U=0)
    # - User page (0x20000000): 4KB page mapping to user_data (U=1)

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
    # PPN = 0x80000 (PA 0x80000000), V=1, R=1, X=1, U=1
    la t0, page_table
    li t1, 512
    slli t1, t1, 2
    add t0, t0, t1
    li t1, 0x80000
    slli t1, t1, 10
    ori t1, t1, 0x1D         # V=1, R=1, X=1, U=1
    sw t1, 0(t0)

    # Entry 64: Kernel page (VA 0x10000000)
    # PPN points to L1 page table for 0x10000000 range
    la t0, page_table
    li t1, 64
    slli t1, t1, 2
    add t0, t0, t1
    la t1, l1_kernel_pt
    srli t1, t1, 2           # Get PPN
    slli t1, t1, 10
    ori t1, t1, 0x01         # V=1 (pointer to next level)
    sw t1, 0(t0)

    # L1 entry 0: Map VA 0x10000000 to kernel_data (U=0)
    la t0, l1_kernel_pt
    la t1, kernel_data
    srli t1, t1, 2           # Get PPN
    slli t1, t1, 10
    ori t1, t1, 0x0F         # V=1, R=1, W=1, U=0 (kernel only!)
    sw t1, 0(t0)

    # Entry 128: User page (VA 0x20000000)
    # PPN points to L1 page table for 0x20000000 range
    la t0, page_table
    li t1, 128
    slli t1, t1, 2
    add t0, t0, t1
    la t1, l1_user_pt
    srli t1, t1, 2           # Get PPN
    slli t1, t1, 10
    ori t1, t1, 0x01         # V=1 (pointer to next level)
    sw t1, 0(t0)

    # L1 entry 0: Map VA 0x20000000 to user_data (U=1)
    la t0, l1_user_pt
    la t1, user_data
    srli t1, t1, 2           # Get PPN
    slli t1, t1, 10
    ori t1, t1, 0x1F         # V=1, R=1, W=1, U=1 (user accessible!)
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

# Page tables (4KB aligned)
page_table:
    .skip 4096

l1_kernel_pt:
    .skip 4096

l1_user_pt:
    .skip 4096

# Data pages (4KB aligned)
.align 12
kernel_data:
    .skip 4096

.align 12
user_data:
    .skip 4096

# Fault counters
.align 4
load_fault_count:
    .word 0

store_fault_count:
    .word 0

# Stacks
.align 12
stack_space:
    .skip 4096
stack_top:

.align 12
trap_stack_space:
    .skip 4096
trap_stack_top:
