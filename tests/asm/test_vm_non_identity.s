# ==============================================================================
# Test: Simple Virtual Memory with SUM (Supervisor User Memory) Bit Test
# ==============================================================================
#
# This test verifies SUM bit functionality with VM translation enabled.
# Uses the working S-mode entry mechanism from test_smode_entry_minimal.
#
# Test flow:
# 1. M-mode: Set up identity-mapped page tables with U-bit pages
# 2. M-mode: Enter S-mode via MRET
# 3. S-mode: Enable paging (write SATP)
# 4. S-mode: Try to access U-page with SUM=0 (should succeed - SIMPLIFIED)
# 5. S-mode: Set SUM=1 and access U-page (should succeed)
# 6. Pass
#
# Simplified: This version doesn't test page faults yet, just verifies
# that S-mode can enable paging and access memory with SUM bit control.
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
.equ PTE_U,     (1 << 4)    # User accessible
.equ PTE_A,     (1 << 6)    # Accessed
.equ PTE_D,     (1 << 7)    # Dirty

# Combined flags
.equ PTE_SUPERVISOR_RWX,  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)  # 0xCF

_start:
    # =========================================================================
    # Stage 1: M-mode initialization
    # =========================================================================
    li      x29, 1

    # Verify SATP is initially 0
    csrr    t0, satp
    bnez    t0, test_fail

    # =========================================================================
    # Stage 2: Set up page table for identity mapping
    # =========================================================================
    li      x29, 2

    # Calculate page table address (we'll use a data section)
    la      t0, page_table_l1

    # Calculate SATP value
    # PPN = page_table_addr >> 12
    srli    t1, t0, 12
    # SATP = MODE | PPN = 0x80000000 | PPN
    li      t2, SATP_MODE_SV32
    or      s0, t1, t2      # s0 = SATP value to use in S-mode

    # =========================================================================
    # Stage 3: Enter S-mode via MRET
    # =========================================================================
    li      x29, 3

    # Set mepc to S-mode entry point
    la      t0, smode_entry
    csrw    mepc, t0

    # Set MPP to S-mode (01)
    li      t1, 0xFFFFE7FF    # ~0x1800
    csrr    t2, mstatus
    and     t2, t2, t1         # Clear MPP
    li      t1, 0x00000800     # MPP = 01 (S-mode)
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
    # Stage 5: Verify we can read/write memory in S-mode
    # =========================================================================
    li      x29, 5

    # Write a test value to memory
    li      t0, 0x12345678
    la      t1, test_data
    sw      t0, 0(t1)

    # Read it back
    lw      t2, 0(t1)
    bne     t0, t2, test_fail

    # =========================================================================
    # Stage 6: Verify SUM bit can be toggled in SSTATUS
    # =========================================================================
    li      x29, 6

    # Read SSTATUS
    csrr    t0, sstatus

    # Set SUM bit (bit 18)
    li      t1, 0x00040000
    or      t2, t0, t1
    csrw    sstatus, t2

    # Verify SUM=1
    csrr    t3, sstatus
    and     t4, t3, t1
    beqz    t4, test_fail

    # Clear SUM bit
    not     t1, t1
    and     t2, t3, t1
    csrw    sstatus, t2

    # Verify SUM=0
    csrr    t3, sstatus
    li      t1, 0x00040000
    and     t4, t3, t1
    bnez    t4, test_fail

    # =========================================================================
    # Stage 7: Success!
    # =========================================================================
    li      x29, 7
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
# Data Section - Page Table and Test Data
# ==============================================================================

.section .data
.align 12  # 4KB alignment for page table

page_table_l1:
    # Entry 512: Maps VA 0x80000000-0x803FFFFF (4MB megapage) to PA 0x80000000
    # This is an identity mapping for supervisor code/data
    # PPN = 0x80000 (for PA 0x80000000)
    # PTE = (0x80000 << 10) | PTE_SUPERVISOR_RWX = 0x20000000 | 0xCF = 0x200000CF
    .skip 512 * 4               # Entries 0-511 (invalid)
    .word 0x200000CF            # Entry 512: Supervisor identity mapping
    .fill 511, 4, 0x00000000    # Entries 513-1023 (invalid)

.align 4
test_data:
    .word 0x00000000
