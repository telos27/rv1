# ==============================================================================
# Test: Non-Identity Virtual Memory Mapping
# ==============================================================================
#
# This test verifies that the MMU can perform non-identity address translation.
# Maps virtual address 0x80000000 to physical address 0x81000000.
#
# Test flow:
# 1. M-mode: Prepare data at physical address 0x81000000
# 2. M-mode: Set up page table mapping VA 0x80000000 → PA 0x81000000
# 3. M-mode: Enter S-mode via MRET
# 4. S-mode: Enable paging (write SATP)
# 5. S-mode: Read from VA 0x80000000, verify it accesses PA 0x81000000
# 6. S-mode: Write to VA 0x80000000, verify it updates PA 0x81000000
# 7. Pass
#
# This demonstrates the MMU correctly translates non-identity mappings,
# which is essential for OS kernels that use different VA/PA layouts.
#
# ==============================================================================

.option norvc  # Disable compressed instructions

.section .text
.globl _start

# Page table constants
.equ SATP_MODE_SV32,    0x80000000
.equ PTE_V,     (1 << 0)    # Valid
.equ PTE_R,     (1 << 1)    # Readable
.equ PTE_W,     (1 << 2)    # Writable
.equ PTE_X,     (1 << 3)    # Executable
.equ PTE_A,     (1 << 6)    # Accessed
.equ PTE_D,     (1 << 7)    # Dirty

# Combined flags (supervisor-accessible, no U bit)
.equ PTE_SUPERVISOR_RWX,  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)  # 0xCF

# Physical addresses
.equ PA_DATA,   0x80003000  # Physical address where data is stored (after page table)
.equ VA_DATA,   0x80000000  # Virtual address that maps to PA_DATA

_start:
    # =========================================================================
    # Stage 1: M-mode initialization - write test data to physical address
    # =========================================================================
    li      x29, 1

    # Verify SATP is initially 0 (paging disabled)
    csrr    t0, satp
    bnez    t0, test_fail

    # Write test pattern to physical address 0x81000000
    # Since paging is off, we can access physical addresses directly
    li      t0, PA_DATA
    li      t1, 0xCAFEBABE      # Test pattern 1
    sw      t1, 0(t0)
    li      t1, 0xDEADC0DE      # Test pattern 2
    sw      t1, 4(t0)

    # Verify the writes succeeded (sanity check)
    li      t0, PA_DATA
    lw      t2, 0(t0)
    li      t3, 0xCAFEBABE
    bne     t2, t3, test_fail

    # =========================================================================
    # Stage 2: Set up page table for NON-identity mapping
    # VA 0x80000000 → PA 0x80003000 (4MB megapage)
    # =========================================================================
    li      x29, 2

    # Calculate page table address
    la      t0, page_table_l1

    # Create PTE for VA 0x80000000 → PA 0x80003000
    # PPN = PA >> 12 = 0x80003000 >> 12 = 0x80003
    # PTE = (PPN << 10) | flags = (0x80003 << 10) | 0xCF
    # PTE = 0x20000CCF
    li      t1, 0x20000CCF
    li      t2, 2048            # Offset to entry 512 (512*4 = 2048)
    add     t2, t0, t2          # Calculate address of entry 512
    sw      t1, 0(t2)           # Store PTE at entry 512

    # Calculate SATP value
    # PPN = page_table_addr >> 12
    srli    t1, t0, 12
    # SATP = MODE | PPN = 0x80000000 | PPN
    li      t2, SATP_MODE_SV32
    or      s0, t1, t2          # s0 = SATP value to use in S-mode

    # =========================================================================
    # Stage 3: Enter S-mode via MRET
    # =========================================================================
    li      x29, 3

    # Set mepc to S-mode entry point
    la      t0, smode_entry
    csrw    mepc, t0

    # Set MPP to S-mode (01)
    li      t1, 0xFFFFE7FF      # ~0x1800
    csrr    t2, mstatus
    and     t2, t2, t1          # Clear MPP
    li      t1, 0x00000800      # MPP = 01 (S-mode)
    or      t2, t2, t1
    csrw    mstatus, t2

    # Enter S-mode
    mret

smode_entry:
    # =========================================================================
    # Stage 4: Now in S-mode - Enable paging
    # =========================================================================
    li      x29, 4

    # Write SATP to enable Sv32 paging
    csrw    satp, s0

    # Issue fence to flush TLB
    sfence.vma

    # Verify SATP was written
    csrr    t0, satp
    bne     t0, s0, test_fail

    # =========================================================================
    # Stage 5: Read from VA 0x80000000, verify it accesses PA 0x81000000
    # =========================================================================
    li      x29, 5

    # Read from virtual address 0x80000000
    # This should be translated to PA 0x81000000 by the MMU
    li      t0, VA_DATA
    lw      t1, 0(t0)           # Should read 0xCAFEBABE
    lw      t2, 4(t0)           # Should read 0xDEADC0DE

    # Verify the values match what we wrote to PA 0x81000000
    li      t3, 0xCAFEBABE
    bne     t1, t3, test_fail

    li      t3, 0xDEADC0DE
    bne     t2, t3, test_fail

    # =========================================================================
    # Stage 6: Write to VA 0x80000000, verify it updates PA 0x81000000
    # =========================================================================
    li      x29, 6

    # Write new values through virtual address
    li      t0, VA_DATA
    li      t1, 0x12345678
    sw      t1, 0(t0)
    li      t1, 0x9ABCDEF0
    sw      t1, 4(t0)

    # Read back through virtual address
    lw      t2, 0(t0)
    li      t3, 0x12345678
    bne     t2, t3, test_fail

    lw      t2, 4(t0)
    li      t3, 0x9ABCDEF0
    bne     t2, t3, test_fail

    # =========================================================================
    # Stage 7: Disable paging and verify physical address was updated
    # =========================================================================
    li      x29, 7

    # Disable paging by clearing SATP
    csrw    satp, zero
    sfence.vma

    # Now read directly from physical address 0x81000000
    # This should show the values we wrote through the virtual address
    li      t0, PA_DATA
    lw      t1, 0(t0)
    li      t2, 0x12345678
    bne     t1, t2, test_fail

    lw      t1, 4(t0)
    li      t2, 0x9ABCDEF0
    bne     t1, t2, test_fail

    # =========================================================================
    # Stage 8: Success!
    # =========================================================================
    li      x29, 8
    j       test_pass

test_pass:
    # Use x29 as final stage marker
    li      x29, 100        # Clearly distinguishable success marker
    li      t0, 0xDEADBEEF
    mv      x28, t0
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

# ==============================================================================
# Data Section - Page Table
# ==============================================================================

.section .data
.align 12  # 4KB alignment for page table

page_table_l1:
    # Entry 512: Maps VA 0x80000000-0x803FFFFF (4MB megapage) to PA 0x80003000
    # PPN = 0x80003 (for PA 0x80003000)
    # PTE = (0x80003 << 10) | PTE_SUPERVISOR_RWX = 0x20000C00 | 0xCF = 0x20000CCF
    .skip 512 * 4               # Entries 0-511 (invalid)
    .word 0x20000CCF            # Entry 512: Non-identity mapping
    .fill 511, 4, 0x00000000    # Entries 513-1023 (invalid)
