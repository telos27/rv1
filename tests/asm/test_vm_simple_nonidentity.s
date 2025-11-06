# ==============================================================================
# Test: Simple Non-Identity Virtual Memory Mapping
# ==============================================================================
#
# Simplified test to verify non-identity VA→PA mapping works:
# - VA 0x90000000 → PA (test_data)
# - Single page, single L0 table, minimal complexity
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
    # STAGE 1: Setup simple 2-level page table
    ###########################################################################

    # Identity map code region (VA 0x80000000 → PA 0x80000000)
    # L1[512] = megapage
    li      t0, 0x200000CF          # PPN=0x80000, flags=V|R|W|X|A|D
    la      t1, page_table_l1
    li      t2, 0x800               # Offset for L1[512]
    add     t1, t1, t2
    sw      t0, 0(t1)

    # L1[576] → L0_table (VA range 0x90000000-0x903FFFFF)
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0x01            # V=1 (non-leaf)
    la      t1, page_table_l1
    li      t2, 0x900               # Offset for L1[576]
    add     t1, t1, t2
    sw      t0, 0(t1)

    # L0[0] → test_data (VA 0x90000000 → PA test_data)
    la      t0, test_data
    srli    t0, t0, 12
    slli    t0, t0, 10
    ori     t0, t0, 0xC7            # V|R|W|A|D
    la      t1, page_table_l0
    sw      t0, 0(t1)               # L0[0]

    # Enable paging
    la      t0, page_table_l1
    srli    t0, t0, 12
    li      t1, 0x80000000          # MODE = Sv32
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma

    TEST_STAGE 2

    ###########################################################################
    # STAGE 2: Write to VA 0x90000000
    ###########################################################################

    li      t0, 0xABCD1234
    li      t1, 0x90000000
    sw      t0, 0(t1)

    TEST_STAGE 3

    ###########################################################################
    # STAGE 3: Read back from VA 0x90000000
    ###########################################################################

    li      t1, 0x90000000
    lw      t2, 0(t1)
    li      t0, 0xABCD1234
    bne     t0, t2, test_fail

    TEST_STAGE 4

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers
###############################################################################

s_trap_handler:
    TEST_FAIL

m_trap_handler:
    TEST_FAIL

###############################################################################
# Data section
###############################################################################
.section .data

TRAP_TEST_DATA_AREA

# Page tables (4KB aligned)
.align 12
page_table_l1:
    .space 4096

.align 12
page_table_l0:
    .space 4096

# Test data (just a single word, no need for full 4KB)
.align 12
test_data:
    .word 0x00000000
