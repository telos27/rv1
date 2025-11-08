# test_pte_permission_rwx.s
# Test PTE permission bits (R/W/X) enforcement
#
# Tests:
#   1. Access invalid page V=0 (should fault - exception code 13 for load)
#   2. Write to read-only page (R=1, W=0) (should fault - exception code 15)
#   3. Execute from non-executable page (R=1, W=1, X=0) (should fault - exception code 12)
#   4. Verify SCAUSE contains correct exception codes
#   5. Verify STVAL contains faulting VA
#
# Note: RISC-V spec says R=W=X=0 with V=1 means "pointer to next level", NOT a leaf PTE.
# So we use V=0 for unmapped pages, and specific R/W/X combos for permission tests.
#
# Expected behavior:
#   - Load from V=0 page: Load page fault (13)
#   - Store to R=1,W=0 page: Store/AMO page fault (15)
#   - Fetch from X=0 page: Instruction page fault (12)

.option norvc                  # Disable compressed instructions

.section .text
.globl _start

_start:
    # Initialize test
    li x28, 0                   # x28 = test result (0 = pass)

    # Setup machine mode trap handler
    la t0, m_trap_handler
    csrw mtvec, t0

    # Setup supervisor mode trap handler
    la t0, s_trap_handler
    csrw stvec, t0

    # Enable supervisor mode traps for page faults
    # Delegate page faults to S-mode
    li t0, (1 << 12) | (1 << 13) | (1 << 15)  # Instruction/Load/Store page faults
    csrw medeleg, t0

    # Setup page tables
    call setup_page_tables

    # Enable paging (Sv32 mode)
    la t0, page_table_root
    srli t0, t0, 12             # Convert to PPN
    li t1, (1 << 31)            # Sv32 mode bit
    or t0, t0, t1
    csrw satp, t0
    sfence.vma                  # Flush TLB

    # Enter supervisor mode
    li t0, 0x00000800           # MSTATUS.MPP = 01 (S-mode)
    csrs mstatus, t0
    li t0, 0x00001800           # Clear MPP field first
    csrc mstatus, t0
    li t0, 0x00000800           # Set MPP = S-mode
    csrs mstatus, t0

    la t0, supervisor_main
    csrw mepc, t0
    mret                        # Jump to supervisor mode

# ============================================================================
# Supervisor Mode Main Test
# ============================================================================
supervisor_main:
    # Initialize test state
    li s0, 0                    # s0 = test stage
    li s1, 0                    # s1 = expected exception code
    li s2, 0                    # s2 = expected faulting VA
    li s3, 0                    # s3 = exception occurred flag

    # ========================================
    # Test 1: Read from invalid page V=0 (should fault)
    # ========================================
    li s0, 1
    li s1, 13                   # Expected: Load page fault
    li s2, 0x10000000           # Expected faulting VA
    li s3, 0                    # Clear exception flag

    li t0, 0x10000000           # VA of invalid page (V=0)
    lw t1, 0(t0)                # Try to read (should fault)

    # If we get here, test failed (no fault occurred)
    li x28, 1
    j test_fail

test1_resume:
    # Verify exception occurred
    li t0, 1
    bne s3, t0, test_fail       # Exception flag should be set

    # ========================================
    # Test 2: Write to read-only page (R=1, W=0, should fault)
    # ========================================
    li s0, 2
    li s1, 15                   # Expected: Store/AMO page fault
    li s2, 0x20000000           # Expected faulting VA
    li s3, 0                    # Clear exception flag

    li t0, 0x20000000           # VA of read-only page (R=1, W=0, X=0)
    li t1, 0xDEADBEEF
    sw t1, 0(t0)                # Try to write (should fault)

    # If we get here, test failed
    li x28, 2
    j test_fail

test2_resume:
    # Verify exception occurred
    li t0, 1
    bne s3, t0, test_fail

    # ========================================
    # Test 3: Execute from non-executable page (X=0, should fault)
    # ========================================
    li s0, 3
    li s1, 12                   # Expected: Instruction page fault
    li s2, 0x30000000           # Expected faulting VA
    li s3, 0                    # Clear exception flag

    li t0, 0x30000000           # VA of non-executable page (R=1, W=1, X=0)
    jalr t0                     # Try to execute (should fault)

    # If we get here, test failed
    li x28, 3
    j test_fail

test3_resume:
    # Verify exception occurred
    li t0, 1
    bne s3, t0, test_fail

    # ========================================
    # Test 4: Read from execute-only page (X=1, R=0, should fault)
    # ========================================
    li s0, 4
    li s1, 13                   # Expected: Load page fault
    li s2, 0x40000000           # Expected faulting VA
    li s3, 0                    # Clear exception flag

    li t0, 0x40000000           # VA of execute-only page (R=0, W=0, X=1)
    lw t1, 0(t0)                # Try to read (should fault - can't read X-only page)

    # If we get here, test failed
    li x28, 4
    j test_fail

test4_resume:
    # Verify exception occurred
    li t0, 1
    bne s3, t0, test_fail

    # ========================================
    # All tests passed!
    # ========================================
    li s0, 100                  # Test complete stage
    j test_pass

# ============================================================================
# Supervisor Mode Trap Handler
# ============================================================================
s_trap_handler:
    # Save context
    csrw sscratch, sp
    la sp, trap_stack_top
    addi sp, sp, -128

    # Check if this is an expected page fault
    csrr t0, scause
    bne t0, s1, unexpected_trap # Should match expected exception code

    csrr t0, stval
    bne t0, s2, unexpected_trap # Should match expected faulting VA

    # Mark that exception occurred
    li s3, 1

    # Resume at appropriate point based on test stage
    li t0, 1
    beq s0, t0, resume_test1
    li t0, 2
    beq s0, t0, resume_test2
    li t0, 3
    beq s0, t0, resume_test3
    li t0, 4
    beq s0, t0, resume_test4

    # Unknown stage
    li x28, 90
    j test_fail

resume_test1:
    la t0, test1_resume
    csrw sepc, t0
    j trap_return

resume_test2:
    la t0, test2_resume
    csrw sepc, t0
    j trap_return

resume_test3:
    la t0, test3_resume
    csrw sepc, t0
    j trap_return

resume_test4:
    la t0, test4_resume
    csrw sepc, t0
    j trap_return

trap_return:
    csrr sp, sscratch
    sret

unexpected_trap:
    # Unexpected trap - fail with stage number
    mv x28, s0
    j test_fail

# ============================================================================
# Machine Mode Trap Handler (should not be reached)
# ============================================================================
m_trap_handler:
    # If we reach M-mode handler, something went wrong
    li x28, 99
    j test_fail

# ============================================================================
# Test Result Handlers
# ============================================================================
test_pass:
    li x28, 0                   # Success
    j write_result

test_fail:
    # x28 already contains error code
    j write_result

write_result:
    # Write result to marker address
    li t0, 0x80002100
    sw x28, 0(t0)

end_loop:
    j end_loop

# ============================================================================
# Page Table Setup
# ============================================================================
setup_page_tables:
    # Setup root page table (level 1)
    la t0, page_table_root

    # Entry 0: Identity map code/data region (0x80000000 - VA[31:22] = 0x200)
    # Megapage: 0x80000000 -> 0x80000000, R=1, W=1, X=1, V=1
    li t1, 0x200
    slli t1, t1, 2              # Index = 0x200 * 4 = byte offset
    add t2, t0, t1
    li t1, 0x20000000           # PPN[1] = 0x200 (0x80000000 >> 12)
    srli t1, t1, 2              # Shift to PPN position
    ori t1, t1, 0x0F            # R=1, W=1, X=1, V=1
    sw t1, 0(t2)

    # Entry for VA 0x10000000 (VPN[1] = 0x040): R=0, W=0, X=0 page
    # Points to level-0 page table
    li t1, 0x040
    slli t1, t1, 2
    add t2, t0, t1
    la t1, page_table_0x10
    srli t1, t1, 12             # Convert to PPN
    slli t1, t1, 10             # Shift to PTE position
    ori t1, t1, 0x01            # V=1 (not a leaf)
    sw t1, 0(t2)

    # Entry for VA 0x20000000 (VPN[1] = 0x080): R=1, W=0 page
    # Points to level-0 page table
    li t1, 0x080
    slli t1, t1, 2
    add t2, t0, t1
    la t1, page_table_0x20
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x01            # V=1
    sw t1, 0(t2)

    # Entry for VA 0x30000000 (VPN[1] = 0x0C0): R=1, W=1, X=0 page
    # Points to level-0 page table
    li t1, 0x0C0
    slli t1, t1, 2
    add t2, t0, t1
    la t1, page_table_0x30
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x01            # V=1
    sw t1, 0(t2)

    # Entry for VA 0x40000000 (VPN[1] = 0x100): R=0, W=0, X=1 page
    # Points to level-0 page table
    li t1, 0x100
    slli t1, t1, 2
    add t2, t0, t1
    la t1, page_table_0x40
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x01            # V=1
    sw t1, 0(t2)

    # Setup level-0 page table for 0x10000000 (V=0 - invalid page)
    la t0, page_table_0x10
    la t1, test_page_data       # Physical page
    srli t1, t1, 12             # Convert to PPN
    slli t1, t1, 10
    ori t1, t1, 0x00            # R=0, W=0, X=0, V=0 (INVALID!)
    sw t1, 0(t0)                # VPN[0] = 0

    # Setup level-0 page table for 0x20000000 (R=1, W=0, X=0)
    la t0, page_table_0x20
    la t1, test_page_data
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x03            # R=1, W=0, X=0, V=1
    sw t1, 0(t0)

    # Setup level-0 page table for 0x30000000 (R=1, W=1, X=0)
    la t0, page_table_0x30
    la t1, test_page_data
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x07            # R=1, W=1, X=0, V=1
    sw t1, 0(t0)

    # Setup level-0 page table for 0x40000000 (R=0, W=0, X=1)
    la t0, page_table_0x40
    la t1, test_page_data
    srli t1, t1, 12
    slli t1, t1, 10
    ori t1, t1, 0x09            # R=0, W=0, X=1, V=1
    sw t1, 0(t0)

    ret

# ============================================================================
# Data Section
# ============================================================================
.section .data

# Note: Marker address is 0x80002100
# Place page tables far enough to avoid corruption
.align 16                       # Align to 64KB boundary

.align 12                       # Page-aligned
page_table_root:
    .space 4096                 # Root page table (1024 entries)

.align 12
page_table_0x10:
    .space 4096                 # Level-0 table for VA 0x10000000

.align 12
page_table_0x20:
    .space 4096                 # Level-0 table for VA 0x20000000

.align 12
page_table_0x30:
    .space 4096                 # Level-0 table for VA 0x30000000

.align 12
page_table_0x40:
    .space 4096                 # Level-0 table for VA 0x40000000

.align 12
test_page_data:
    .word 0x12345678            # Test data
    .space 4092

.align 12
trap_stack:
    .space 4096
trap_stack_top:
