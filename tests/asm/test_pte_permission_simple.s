# test_pte_permission_simple.s
# Simplified PTE permission test - verify R/W/X bits are enforced
# Based on test_sum_minimal.s template

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.equ SATP_MODE_SV32, 0x80000000
.equ PTE_V, (1 << 0)
.equ PTE_R, (1 << 1)
.equ PTE_W, (1 << 2)
.equ PTE_X, (1 << 3)
.equ PTE_A, (1 << 6)
.equ PTE_D, (1 << 7)
.equ CAUSE_STORE_PAGE_FAULT, 15

.section .data
.align 12
page_table:
    # Entry 512: Maps VA 0x80000000 to PA 0x80000000 (code/data, R/W/X)
    .fill 512, 4, 0
    .word 0x200000CF            # PPN=0x20000, R=1, W=1, X=1, A=1, D=1, V=1
    .fill 511, 4, 0

.align 12
test_page:
    .word 0xDEADBEEF

.align 12
readonly_pt:
    # Level-0 page table for read-only page
    .word 0x20005403            # Points to test_page, R=1, W=0, X=0, V=1

fault_occurred:
    .word 0

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Setup S-mode trap handler
    la t0, s_trap_handler
    csrw stvec, t0

    # Delegate page faults to S-mode
    li t0, (1 << 15)            # Store/AMO page fault
    csrw medeleg, t0

    TEST_STAGE 2

    # Enter S-mode
    ENTER_SMODE_M smode_test

smode_test:
    TEST_STAGE 3

    # Setup page table: Map VA 0x10000000 as read-only
    # First, setup root page table entry for VA 0x10000000 (VPN[1]=0x040)
    la t0, page_table
    la t1, readonly_pt
    srli t1, t1, 12             # Get PPN
    slli t1, t1, 10             # Shift to PTE position
    ori t1, t1, PTE_V           # V=1 (pointer to next level)
    sw t1, (64*4)(t0)           # Entry 64 for VPN[1]=0x040

    # Enable paging
    la t0, page_table
    srli t0, t0, 12
    li t1, SATP_MODE_SV32
    or t0, t0, t1
    csrw satp, t0
    sfence.vma

    TEST_STAGE 4

    # Test: Try to write to read-only page (should fault)
    li t0, 0x10000000
    li t1, 0x12345678
    sw t1, 0(t0)                # Should cause Store/AMO page fault

    # If we get here, test failed (write should have faulted)
    TEST_FAIL

s_trap_handler:
    # Verify this is the expected store page fault
    csrr t0, scause
    li t1, CAUSE_STORE_PAGE_FAULT
    bne t0, t1, test_fail

    # Verify faulting address
    csrr t0, stval
    li t1, 0x10000000
    bne t0, t1, test_fail

    # Mark fault occurred
    la t0, fault_occurred
    li t1, 1
    sw t1, 0(t0)

    # All tests passed!
    TEST_STAGE 100
    TEST_PASS

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
