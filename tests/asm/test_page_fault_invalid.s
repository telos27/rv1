# Test: Page fault on invalid PTE
.include "tests/asm/include/priv_test_macros.s"
.option norvc

.equ SATP_MODE_SV32, 0x80000000
.equ CAUSE_LOAD_PAGE_FAULT, 13

.section .data
.align 12
page_table:
    # Entry 0: INVALID (V=0)
    .word 0x00000000
    .fill 511, 4, 0x00000000

    # Entry 512: Valid entry for code
    .word 0x200000CF
    .fill 511, 4, 0x00000000

.align 4
fault_count:
    .word 0

.section .text
.globl _start

_start:
    TEST_STAGE 1

    # Enter S-mode
    SET_STVEC_DIRECT s_trap
    ENTER_SMODE_M smode_entry

smode_entry:
    TEST_STAGE 2

    # Enable paging
    la      t0, page_table
    srli    t0, t0, 12
    li      t1, SATP_MODE_SV32
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    TEST_STAGE 3

    # Try to access invalid page (should fault)
    li      t0, 0x00001000  # VA in entry 0's range (invalid PTE)
    lw      t1, 0(t0)       # This should cause load page fault!

    # If we get here, test failed
    j       test_fail

smode_after_fault:
    TEST_STAGE 4

    # Verify fault count is 1
    la      t0, fault_count
    lw      t1, 0(t0)
    li      t2, 1
    bne     t1, t2, test_fail

    TEST_STAGE 5
    TEST_PASS

test_fail:
    TEST_FAIL

s_trap:
    # Check if it's a load page fault
    csrr    t0, scause
    li      t1, CAUSE_LOAD_PAGE_FAULT
    bne     t0, t1, test_fail

    # Increment fault count
    la      t2, fault_count
    lw      t3, 0(t2)
    addi    t3, t3, 1
    sw      t3, 0(t2)

    # Return to after the faulting instruction
    la      t0, smode_after_fault
    csrw    sepc, t0
    sret

TRAP_TEST_DATA_AREA
