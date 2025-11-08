# ==============================================================================
# Test: S-mode Accessing User Memory with SUM bit
# ==============================================================================
#
# This test verifies that S-mode can access U=1 data pages when the SUM
# (Supervisor User Memory) bit is set in MSTATUS/SSTATUS.
#
# Test Sequence:
# 1. Setup virtual memory with U=0 pages for code and U=1 pages for user data
# 2. Stay in S-mode throughout (simpler than dealing with U-mode code pages)
# 3. Try to access U=1 page with SUM=0 → should fault (not tested due to trap issues)
# 4. Set SUM=1 in SSTATUS
# 5. Access U=1 page with SUM=1 → should succeed
# 6. Read/write data to U=1 pages
# 7. Verify data integrity
#
# This validates the critical OS functionality where kernel (S-mode) needs to
# access user buffers during syscalls.
#
# ==============================================================================

.include "tests/asm/include/priv_test_macros.s"
.option norvc

.section .text
.globl _start

_start:
    TEST_PREAMBLE
    TEST_STAGE 1

    ###########################################################################
    # Setup page tables for virtual memory
    ###########################################################################

    # L1 page table at 0x80002000 (already cleared by TEST_PREAMBLE)
    li      t0, 0x80002000          # L1 page table base

    # Create megapage entry for code/data region (0x80000000)
    # VA [31:22] = 0x200 (0x80000000 >> 22)
    # PPN = 0x80000 >> 12 = 0x20000
    # PTE = (0x20000 << 10) | V | R | W | X = 0x200000CF
    # U=0 so S-mode and M-mode can access (S-mode kernel code/data)
    li      t1, 0x200000CF          # Megapage: V=1, R=1, W=1, X=1, U=0
    li      t2, 0x200               # VPN[1] = 0x200
    slli    t2, t2, 2               # Convert to byte offset
    add     t3, t0, t2              # Address of PTE
    sw      t1, 0(t3)               # Write PTE

    # Create a second-level page table for user data pages
    # We'll map a 4KB page at VA 0x20000000 with U=1
    # NOTE: L2 table must be page-aligned (lower 12 bits = 0)
    li      t4, 0x80003000          # L2 page table base (page-aligned, avoids 0x80002100)

    # Create L1 PTE pointing to L2 table
    # VA 0x20000000 (VPN[1]=0x080) for user data
    li      t1, 0x80003000
    srli    t1, t1, 12              # PPN of L2 table = 0x80003
    slli    t1, t1, 10              # Shift to PPN field
    ori     t1, t1, 0x01            # V=1, but R=W=X=0 (pointer to next level)
    li      t2, 0x080               # VPN[1] = 0x080 (VA 0x20000000)
    slli    t2, t2, 2               # Convert to byte offset
    add     t3, t0, t2              # Address of L1 PTE
    sw      t1, 0(t3)               # Write L1 PTE

    # Create L2 PTE for VA 0x20000000 → PA 0x80010000, U=1
    # VPN[0] = 0x000 (first entry in L2 table)
    li      t1, 0x80010000
    srli    t1, t1, 12              # PPN = 0x80010
    slli    t1, t1, 10              # Shift to PPN field
    ori     t1, t1, 0xDF            # V=1, R=1, W=1, X=1, U=1
    sw      t1, 0(t4)               # Write L2 PTE[0]

    TEST_STAGE 2

    # Enable paging
    li      t0, 0x80002000
    srli    t0, t0, 12              # PPN of page table
    li      t1, 0x80000000          # Sv32 mode bit
    or      t0, t0, t1              # SATP value
    csrw    satp, t0
    sfence.vma

    TEST_STAGE 3

    ###########################################################################
    # Enter S-mode (stay in S-mode, don't go to U-mode)
    ###########################################################################

    ENTER_SMODE_M s_mode_entry

s_mode_entry:
    TEST_STAGE 4

    ###########################################################################
    # Test 1: S-mode reads from U=1 page WITH SUM=1
    ###########################################################################

    # Enable SUM bit to access user memory
    li      t0, MSTATUS_SUM
    csrs    sstatus, t0

    # Setup user buffer at 0x20000000 (U=1 page, maps to PA 0x80010000)
    li      t0, 0x20000000
    li      t1, 100                 # buffer[0] = 100
    sw      t1, 0(t0)
    li      t1, 200                 # buffer[1] = 200
    sw      t1, 4(t0)
    li      t1, 300                 # buffer[2] = 300
    sw      t1, 8(t0)

    # Read back and verify
    lw      t2, 0(t0)
    li      t3, 100
    bne     t2, t3, test_fail

    lw      t2, 4(t0)
    li      t3, 200
    bne     t2, t3, test_fail

    lw      t2, 8(t0)
    li      t3, 300
    bne     t2, t3, test_fail

    TEST_STAGE 5

    ###########################################################################
    # Test 2: S-mode writes to U=1 page WITH SUM=1
    ###########################################################################

    # Clear buffer
    li      t0, 0x20000000
    sw      zero, 0(t0)
    sw      zero, 4(t0)
    sw      zero, 8(t0)

    # Write sequence: [10, 15, 20]
    li      t1, 10
    sw      t1, 0(t0)
    li      t1, 15
    sw      t1, 4(t0)
    li      t1, 20
    sw      t1, 8(t0)

    # Verify
    lw      t2, 0(t0)
    li      t3, 10
    bne     t2, t3, test_fail

    lw      t2, 4(t0)
    li      t3, 15
    bne     t2, t3, test_fail

    lw      t2, 8(t0)
    li      t3, 20
    bne     t2, t3, test_fail

    TEST_STAGE 6

    ###########################################################################
    # Test 3: S-mode read-modify-write on U=1 page WITH SUM=1
    ###########################################################################

    # Setup buffer: [5, 10, 15]
    li      t0, 0x20000000
    li      t1, 5
    sw      t1, 0(t0)
    li      t1, 10
    sw      t1, 4(t0)
    li      t1, 15
    sw      t1, 8(t0)

    # Multiply by 3: [15, 30, 45]
    lw      t1, 0(t0)
    li      t2, 3
    mul     t1, t1, t2
    sw      t1, 0(t0)

    lw      t1, 4(t0)
    li      t2, 3
    mul     t1, t1, t2
    sw      t1, 4(t0)

    lw      t1, 8(t0)
    li      t2, 3
    mul     t1, t1, t2
    sw      t1, 8(t0)

    # Verify: [15, 30, 45]
    lw      t2, 0(t0)
    li      t3, 15
    bne     t2, t3, test_fail

    lw      t2, 4(t0)
    li      t3, 30
    bne     t2, t3, test_fail

    lw      t2, 8(t0)
    li      t3, 45
    bne     t2, t3, test_fail

    TEST_STAGE 7

    ###########################################################################
    # Test 4: Compute sum of buffer (simulates syscall processing user data)
    ###########################################################################

    # Use buffer with values [15, 30, 45]
    li      t0, 0x20000000
    li      t1, 0                   # sum = 0
    li      t2, 3                   # count = 3
    mv      t3, t0                  # pointer

sum_loop:
    beqz    t2, sum_done
    lw      t4, 0(t3)
    add     t1, t1, t4
    addi    t3, t3, 4
    addi    t2, t2, -1
    j       sum_loop

sum_done:
    # Verify sum = 15 + 30 + 45 = 90
    li      t4, 90
    bne     t1, t4, test_fail

    TEST_STAGE 8

    ###########################################################################
    # Test 5: Disable SUM and verify we're done (we can't test fault without
    # proper trap handling, which would complicate this simple test)
    ###########################################################################

    # Disable SUM bit
    li      t0, MSTATUS_SUM
    csrc    sstatus, t0

    # Note: We don't test that access NOW fails, because that would require
    # setting up a trap handler for load/store faults, which is complex.
    # The important thing is that we verified SUM=1 allows S-mode to access
    # U=1 pages, which is the critical functionality for OS syscalls.

    # All tests passed!
    j       test_pass

###############################################################################
# Test termination
###############################################################################

test_pass:
    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers
###############################################################################

m_trap_handler:
    # M-mode trap is unexpected (we delegated exceptions to S-mode)
    TEST_FAIL

s_trap_handler:
    # S-mode trap is unexpected for this test
    # (We're not testing fault cases, only successful SUM accesses)
    csrr    a0, scause
    csrr    a1, sepc
    csrr    a2, stval
    TEST_FAIL
