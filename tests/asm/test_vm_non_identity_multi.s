# ==============================================================================
# Test: Multiple Non-Identity Virtual Memory Mappings
# ==============================================================================
#
# This test verifies that the MMU can perform multiple non-identity address
# translations simultaneously and that the TLB correctly caches all mappings.
#
# Memory layout (fits within 16KB DMEM):
# - L1 page table: 4KB @ 0x80001000
# - L2 table #1:   4KB @ 0x80002000
# - L2 table #2:   256B @ 0x80003000 (only first entry used)
# - test_data_area1: 8B @ 0x80003100
# - test_data_area2: 8B @ 0x80003200
#
# Test flow:
# 1. M-mode: Prepare test data at 2 different physical addresses
# 2. M-mode: Set up page table with THREE mappings:
#    - VA 0x80000000 → PA 0x80000000 (identity map for code)
#    - VA 0x90000000 → PA test_data_area1 (non-identity map #1)
#    - VA 0xA0000000 → PA test_data_area2 (non-identity map #2)
# 3. M-mode: Enter S-mode via MRET
# 4. S-mode: Enable paging (write SATP)
# 5. S-mode: Access both non-identity mappings and verify correct translation
# 6. S-mode: Write through both mappings
# 7. S-mode: Disable paging and verify physical addresses were updated
# 8. Pass
#
# This demonstrates the MMU and TLB can handle multiple distinct VA→PA
# translations, which is essential for OS memory management.
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

# Combined flags
.equ PTE_SUPERVISOR_RWX,  (PTE_V | PTE_R | PTE_W | PTE_X | PTE_A | PTE_D)  # 0xCF

# Virtual addresses
.equ VA_DATA1,  0x90000000
.equ VA_DATA2,  0xA0000000

_start:
    # =========================================================================
    # Stage 1: M-mode initialization
    # =========================================================================
    li      x29, 1

    # Verify SATP is initially 0
    csrr    t0, satp
    bnez    t0, test_fail

    # Write test patterns
    la      t0, test_data_area1
    li      t1, 0xCAFEBABE
    sw      t1, 0(t0)
    li      t1, 0xDEADC0DE
    sw      t1, 4(t0)

    la      t0, test_data_area2
    li      t1, 0x11111111
    sw      t1, 0(t0)
    li      t1, 0x22222222
    sw      t1, 4(t0)

    # Verify write
    la      t0, test_data_area1
    lw      t2, 0(t0)
    li      t3, 0xCAFEBABE
    bne     t2, t3, test_fail

    # Save physical addresses
    la      s1, test_data_area1
    la      s2, test_data_area2

    # =========================================================================
    # Stage 2: Set up page table
    # =========================================================================
    li      x29, 2

    la      t0, page_table_l1
    la      t3, page_table_l2_1
    la      t4, page_table_l2_2

    # L1 Entry 512: Identity megapage (VA 0x80000000 → PA 0x80000000)
    li      t1, 0x200000CF
    li      t2, 2048
    add     t2, t0, t2
    sw      t1, 0(t2)

    # L1 Entry 576: Pointer to L2 table #1
    srli    t6, t3, 12
    slli    t1, t6, 10
    ori     t1, t1, 0x01
    li      t2, 2304
    add     t2, t0, t2
    sw      t1, 0(t2)

    # L1 Entry 640: Pointer to L2 table #2
    srli    t6, t4, 12
    slli    t1, t6, 10
    ori     t1, t1, 0x01
    li      t2, 2560
    add     t2, t0, t2
    sw      t1, 0(t2)

    # L2 Table #1 Entry 0: VA 0x90000000 → PA test_data_area1
    srli    t6, s1, 12
    slli    t1, t6, 10
    ori     t1, t1, 0xCF
    sw      t1, 0(t3)

    # L2 Table #2 Entry 0: VA 0xA0000000 → PA test_data_area2
    srli    t6, s2, 12
    slli    t1, t6, 10
    ori     t1, t1, 0xCF
    sw      t1, 0(t4)

    # Calculate SATP
    srli    t1, t0, 12
    li      t2, SATP_MODE_SV32
    or      s0, t1, t2

    # =========================================================================
    # Stage 3: Enter S-mode
    # =========================================================================
    li      x29, 3

    la      t0, smode_entry
    csrw    mepc, t0

    li      t1, 0xFFFFE7FF
    csrr    t2, mstatus
    and     t2, t2, t1
    li      t1, 0x00000800
    or      t2, t2, t1
    csrw    mstatus, t2

    mret

smode_entry:
    # =========================================================================
    # Stage 4: Enable paging
    # =========================================================================
    li      x29, 4

    csrw    satp, s0
    sfence.vma

    csrr    t0, satp
    bne     t0, s0, test_fail

    # =========================================================================
    # Stage 5: Read from both VAs
    # =========================================================================
    li      x29, 5

    li      t0, VA_DATA1
    lw      t1, 0(t0)
    lw      t2, 4(t0)
    li      t3, 0xCAFEBABE
    bne     t1, t3, test_fail
    li      t3, 0xDEADC0DE
    bne     t2, t3, test_fail

    li      t0, VA_DATA2
    lw      t1, 0(t0)
    lw      t2, 4(t0)
    li      t3, 0x11111111
    bne     t1, t3, test_fail
    li      t3, 0x22222222
    bne     t2, t3, test_fail

    # =========================================================================
    # Stage 6: Write through both VAs
    # =========================================================================
    li      x29, 6

    li      t0, VA_DATA1
    li      t1, 0x12345678
    sw      t1, 0(t0)
    li      t1, 0x9ABCDEF0
    sw      t1, 4(t0)

    li      t0, VA_DATA2
    li      t1, 0x33333333
    sw      t1, 0(t0)
    li      t1, 0x44444444
    sw      t1, 4(t0)

    # Read back
    li      t0, VA_DATA1
    lw      t1, 0(t0)
    li      t2, 0x12345678
    bne     t1, t2, test_fail
    lw      t1, 4(t0)
    li      t2, 0x9ABCDEF0
    bne     t1, t2, test_fail

    li      t0, VA_DATA2
    lw      t1, 0(t0)
    li      t2, 0x33333333
    bne     t1, t2, test_fail
    lw      t1, 4(t0)
    li      t2, 0x44444444
    bne     t1, t2, test_fail

    # =========================================================================
    # Stage 7: Disable paging and verify PAs
    # =========================================================================
    li      x29, 7

    csrw    satp, zero
    sfence.vma

    la      t0, test_data_area1
    lw      t1, 0(t0)
    li      t2, 0x12345678
    bne     t1, t2, test_fail
    lw      t1, 4(t0)
    li      t2, 0x9ABCDEF0
    bne     t1, t2, test_fail

    la      t0, test_data_area2
    lw      t1, 0(t0)
    li      t2, 0x33333333
    bne     t1, t2, test_fail
    lw      t1, 4(t0)
    li      t2, 0x44444444
    bne     t1, t2, test_fail

    # =========================================================================
    # Stage 8: Success
    # =========================================================================
    li      x29, 8
    j       test_pass

test_pass:
    li      x29, 100
    li      t0, 0xDEADBEEF
    mv      x28, t0
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    ebreak

# ==============================================================================
# Data Section
# ==============================================================================

.section .data
.align 12

page_table_l1:
    .fill 1024, 4, 0x00000000

.align 12
page_table_l2_1:
    .fill 4, 4, 0x00000000

# L2 table #2 doesn't need 4KB alignment - it just needs to be page-aligned
# for the PPN calculation to work correctly. However, we'll align it anyway
# to keep the design clean and avoid any potential issues.
.align 12
page_table_l2_2:
    .fill 4, 4, 0x00000000

# Test data areas - these are small and don't need page alignment
# They can be anywhere in physical memory
test_data_area1:
    .word 0x00000000
    .word 0x00000000

test_data_area2:
    .word 0x00000000
    .word 0x00000000
