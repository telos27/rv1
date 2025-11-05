# Simple VM debug test - check exactly what fails
.option norvc

.section .text
.globl _start

_start:
    # Stage marker: 1 = start
    li      t4, 1

    # Check 1: SATP should be 0
    csrr    t0, satp
    # Store SATP value in t5 for inspection
    mv      t5, t0
    # If SATP != 0, jump to satp_fail
    bnez    t0, satp_fail

    # Stage marker: 2 = SATP check passed
    li      t4, 2

    # Check 2: Memory write/read
    li      t1, 0x12345678
    li      t2, 0x80002000
    sw      t1, 0(t2)

    # Stage marker: 3 = write done
    li      t4, 3

    # Read back
    lw      t3, 0(t2)

    # Stage marker: 4 = read done
    li      t4, 4

    # Compare
    bne     t1, t3, mem_fail

    # Stage marker: 5 = all checks passed
    li      t4, 5

pass:
    li      t3, 0xDEADBEEF
    ebreak

satp_fail:
    # t4=1 or 2, t5=SATP value, t3=fail marker
    li      t6, 0xBAD0
    li      t3, 0xDEADDEAD
    ebreak

mem_fail:
    # t4=3 or 4, t1=expected, t3=actual, t3 will be overwritten with fail marker
    li      t6, 0xBAD1
    mv      t0, t3  # Save actual value in t0
    li      t3, 0xDEADDEAD
    ebreak

.section .data
.align 12
# Dummy page table (won't be used)
dummy_data:
    .fill 4096, 1, 0
