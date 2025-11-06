# Simple SUM bit test - debug version
# Just checks if S-mode can access U-pages with SUM=0

.option norvc

.section .text
.globl _start

_start:
    li      x29, 1          # Stage 1: M-mode setup

    # Simple identity map with U=1 page
    # L1 entry 512: Map VA 0x80000000 (code region) as megapage
    la      t0, page_table_l1
    li      t1, 0x200000CF  # PPN=0x80000, flags=V|R|W|X|A|D
    li      t4, 2048        # Entry 512 * 4 bytes = offset 2048
    add     t4, t0, t4
    sw      t1, 0(t4)

    li      x29, 11         # Stage 1.1: L1 entry written

    # L1 entry 0: Point to L2 for VA 0x00000000-0x003FFFFF
    la      t2, page_table_l2
    srli    t2, t2, 12
    slli    t2, t2, 10
    ori     t2, t2, 0x01    # V=1 only (non-leaf)
    sw      t2, 0(t0)

    li      x29, 12         # Stage 1.2: L2 pointer written

    # L2 entry 4: Map VA 0x00004000 with U=1
    la      t2, page_table_l2
    la      t3, test_data
    srli    t3, t3, 12
    slli    t3, t3, 10
    ori     t3, t3, 0xD7    # V|R|W|U|A|D (no X)
    sw      t3, 16(t2)      # Entry 4 * 4 bytes = offset 16

    li      x29, 13         # Stage 1.3: L2 entry written

    # Write test data from M-mode
    li      t0, 0xABCD1234
    la      t1, test_data
    sw      t0, 0(t1)

    li      x29, 2          # Stage 2: Enable paging

    # Enable Sv32
    la      t0, page_table_l1
    srli    t0, t0, 12
    li      t1, 0x80000000
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    # Verify M-mode can still access
    la      t0, test_data
    lw      t1, 0(t0)
    li      t2, 0xABCD1234
    bne     t1, t2, fail

    li      x29, 3          # Stage 3: Try S-mode access

    # Clear SUM bit
    li      t0, (1 << 18)   # MSTATUS_SUM
    csrrc   zero, mstatus, t0

    # Enter S-mode
    la      t0, smode_test
    csrw    mepc, t0
    li      t1, (1 << 11)   # MPP = S-mode
    csrr    t2, mstatus
    li      t3, ~0x1800
    and     t2, t2, t3
    or      t2, t2, t1
    csrw    mstatus, t2
    mret

smode_test:
    li      x29, 4          # Stage 4: S-mode, try access

    # This should fault if SUM is working
    li      t0, 0x00004000
    lw      t1, 0(t0)       # Access U-page from S-mode with SUM=0

    # If we get here, SUM check failed - should have faulted
    li      x29, 99         # Error indicator
    j       fail

pass:
    li      x28, 0xDEADBEEF
    ebreak

fail:
    li      x28, 0xDEADDEAD
    ebreak

.section .data
.align 12
page_table_l1:
    .skip 4096

page_table_l2:
    .skip 4096

.align 12
test_data:
    .word 0
    .skip 4092
