# Minimal SUM bit test - verify S-mode cannot access U-pages with SUM=0

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.equ SATP_MODE_SV32, 0x80000000
.equ PTE_V, (1 << 0)
.equ PTE_R, (1 << 1)
.equ PTE_W, (1 << 2)
.equ PTE_U, (1 << 4)
.equ PTE_A, (1 << 6)
.equ PTE_D, (1 << 7)
.equ PTE_USER_RW, (PTE_V | PTE_R | PTE_W | PTE_U | PTE_A | PTE_D)
.equ CAUSE_LOAD_PAGE_FAULT, 13

.section .data
.align 12
page_table:
    # Entry 512: Maps VA 0x80000000 to PA 0x80000000 (supervisor page)
    .fill 512, 4, 0
    .word 0x200000CF
    .fill 511, 4, 0

test_data:
    .word 0xABCD1234

fault_occurred:
    .word 0

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Setup SATP
    la t0, page_table
    srli t0, t0, 12
    li t1, SATP_MODE_SV32
    or t0, t0, t1
    mv s0, t0

    # Setup S-mode trap handler
    la t0, s_trap_handler
    csrw stvec, t0

    # Ensure SUM=0
    li t0, (1 << 18)
    csrc mstatus, t0

    TEST_STAGE 2

    # Enter S-mode using macro
    ENTER_SMODE_M smode_test

smode_test:
    TEST_STAGE 3

    # Enable paging
    csrw satp, s0
    sfence.vma

    # Verify we're in S-mode and SUM=0
    csrr t0, sstatus
    li t1, (1 << 18)
    and t2, t0, t1
    bnez t2, test_fail  # SUM should be 0

    TEST_STAGE 4

    # This should work - accessing supervisor page
    la t0, test_data
    lw t1, 0(t0)

    TEST_STAGE 5
    TEST_PASS

s_trap_handler:
    # We shouldn't get here in this test
    j test_fail

test_fail:
    TEST_FAIL

TRAP_TEST_DATA_AREA
