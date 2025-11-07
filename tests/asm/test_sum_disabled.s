# ==============================================================================
# Test: SUM (Supervisor User Memory) Bit Disabled - Should Fault
# ==============================================================================
#
# This test verifies that when MSTATUS.SUM = 0, S-mode cannot access
# U-mode accessible memory (pages with PTE.U = 1).
#
# Test Sequence:
# 1. Setup page table with U=1 page (user-accessible)
# 2. Write data to that page from M-mode (should work, M-mode ignores U bit)
# 3. Enter S-mode with SUM=0
# 4. Try to read from U=1 page (should trigger load page fault, code 13)
# 5. Trap handler verifies correct exception
# 6. Try to write to U=1 page (should trigger store page fault, code 15)
# 7. Trap handler verifies correct exception
# 8. Test passes if both faults occur correctly
#
# CRITICAL: This is a blocker for xv6 - kernel must be able to control
# access to user memory. Without SUM working, kernel can't safely access
# user stacks during syscalls.
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
    # Setup page table with U=1 (user-accessible) page
    ###########################################################################

    # Create a 2-level page table (Sv32)
    # Level 1 (root): Points to level 0 page table
    # Level 0: Contains entry for test page at VA 0x10000000

    # L1 entry 0: Points to L0 page table for VA range 0x00000000-0x003FFFFF
    # PTE format: [31:10] = PPN[1:0], [7:0] = flags
    # Flags: V=1, no leaf (points to next level)
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field position
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table address
    # Note: L1[512] megapage entry for 0x80000000 is pre-populated in .data section

    # L0 entry for VA 0x00010000 (VPN[0] = 0x10):
    # Map to physical page containing user_test_data
    # Flags: V=1, R=1, W=1, X=0, U=1 (user-accessible), A=1, D=1
    # Permission: 0xCF => V|R|W|X|U|A|D = 0x01|0x02|0x04|0x00|0x10|0x40|0x80 = 0xD7
    la      t0, user_test_data
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0xD7            # V|R|W|U|A|D (no X, yes U)
    la      t1, page_table_l0
    sw      t0, (0x10 * 4)(t1)      # L0[0x10] for VA 0x00010000

    TEST_STAGE 2

    ###########################################################################
    # M-mode: Write test data to U=1 page BEFORE enabling paging
    # NOTE: M-mode ALWAYS bypasses address translation (RISC-V spec 4.4.1)
    # So we must write to the PHYSICAL address before enabling paging
    ###########################################################################

    li      t0, 0xABCD1234          # Test value
    la      t1, user_test_data      # Physical address of user data
    sw      t0, 0(t1)               # Write to physical address (paging not yet enabled)
    lw      t2, 0(t1)               # Read back (Session 114: bus adapter handles registered memory timing)
    bne     t0, t2, test_fail       # Verify write succeeded

    TEST_STAGE 3

    ###########################################################################
    # Enable paging AFTER M-mode setup
    ###########################################################################

    # Enable paging with SATP
    # SATP format: MODE[31]=1 (Sv32), ASID[30:22]=0, PPN[21:0]=root_ppn
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma                      # Flush TLB

    TEST_STAGE 4

    ###########################################################################
    # Setup trap handler to expect page faults
    ###########################################################################

    # Set flag to indicate we're expecting a fault
    la      t0, expect_fault_flag
    li      t1, 1
    sw      t1, 0(t0)
    nop                              # Session 114: Registered memory timing
    nop
    nop

    # Save the expected exception cause (will be checked in handler)
    la      t0, expected_cause
    li      t1, CAUSE_LOAD_PAGE_FAULT
    sw      t1, 0(t0)
    nop                              # Session 114: Registered memory timing
    nop
    nop

    TEST_STAGE 5

    ###########################################################################
    # Enter S-mode with SUM=0 (disabled)
    ###########################################################################

    # Ensure SUM bit is 0
    DISABLE_SUM

    # Delegate page faults to S-mode so we can test S-mode trap handling
    # (Otherwise faults go to M-mode, which is also valid but not what we want to test)
    DELEGATE_EXCEPTION CAUSE_LOAD_PAGE_FAULT
    DELEGATE_EXCEPTION CAUSE_STORE_PAGE_FAULT

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    TEST_STAGE 6

    ###########################################################################
    # S-mode test 1: Try to READ from U=1 page (should fault)
    ###########################################################################

try_load:
    li      t1, 0x00010000          # VA of user page
    lw      t2, 0(t1)               # This should trigger load page fault!

    # If we get here, something is wrong - should have faulted
    j       test_fail

after_load_fault:
    TEST_STAGE 7

    ###########################################################################
    # S-mode test 2: Try to WRITE to U=1 page (should fault)
    ###########################################################################

    # Update expected cause for store fault
    la      t0, expected_cause
    li      t1, CAUSE_STORE_PAGE_FAULT
    sw      t1, 0(t0)
    nop                              # Session 114: Registered memory timing
    nop
    nop

try_store:
    li      t0, 0xDEAD5678          # Different test value
    li      t1, 0x00010000          # VA of user page
    sw      t0, 0(t1)               # This should trigger store page fault!

    # If we get here, something is wrong - should have faulted
    j       test_fail

after_store_fault:
    TEST_STAGE 8

    ###########################################################################
    # Both faults occurred correctly - test passes!
    ###########################################################################

    TEST_PASS

###############################################################################
# S-mode trap handler
###############################################################################
s_trap_handler:
    # Save which test we were on
    la      t0, trap_stage
    sw      x29, 0(t0)

    # Check if we were expecting a fault
    la      t0, expect_fault_flag
    lw      t1, 0(t0)
    beqz    t1, test_fail           # Unexpected trap!

    # Verify the exception cause matches expected
    csrr    t0, scause
    la      t1, expected_cause
    lw      t2, 0(t1)
    bne     t0, t2, test_fail       # Wrong exception type!

    # Verify STVAL contains the faulting address (0x00010000)
    csrr    t0, stval
    li      t1, 0x00010000
    bne     t0, t1, test_fail       # Wrong faulting address!

    # Increment trap counter
    la      t0, trap_count
    lw      t1, 0(t0)
    addi    t1, t1, 1
    sw      t1, 0(t0)
    # Session 114: Bus adapter now handles registered memory timing automatically
    # Determine which fault this was and set return address
    lw      t2, 0(t0)               # Get trap_count
    li      t3, 1
    beq     t2, t3, handle_first_fault
    li      t3, 2
    beq     t2, t3, handle_second_fault

    # Unexpected trap count
    j       test_fail

handle_first_fault:
    # First fault (load at try_load) - skip the LW instruction (4 bytes) and continue
    # Actually, let's jump to after_load_fault label for clarity
    la      t0, after_load_fault
    csrw    sepc, t0
    sret

handle_second_fault:
    # Second fault (store at try_store) - jump to after_store_fault
    la      t0, after_store_fault
    csrw    sepc, t0
    sret

###############################################################################
# M-mode trap handler (should not be reached - exceptions delegated to S)
###############################################################################
m_trap_handler:
    # Save diagnostic info
    csrr    a0, mcause
    csrr    a1, mepc
    csrr    a2, mtval

    # M-mode trap is unexpected (we delegated to S-mode)
    TEST_FAIL

test_fail:
    TEST_FAIL

###############################################################################
# Data section
###############################################################################
.section .data
.align 12  # Page align

# Level 1 page table (root)
page_table_l1:
    # Entry 0: Points to L0 page table (will be filled at runtime)
    .word 0x00000000
    # Entries 1-511: Reserved
    .fill 511, 4, 0x00000000
    # Entry 512 (0x200): Megapage for VA 0x80000000-0x803FFFFF (identity mapped)
    # PPN = 0x80000, flags = V|R|W|X|A|D = 0xCF
    .word 0x200000CF
    # Entries 513-1023: Invalid
    .fill 511, 4, 0x00000000

# Level 0 page table
page_table_l0:
    .skip 4096  # 1024 entries x 4 bytes

# User-accessible test data (will be mapped with U=1)
.align 12  # Page align (must be on page boundary)
user_test_data:
    .word 0x00000000
    .skip 4092  # Fill rest of page

# Test control variables
.align 4
expect_fault_flag:
    .word 0

trap_stage:
    .word 0

# Use standard data area from macros
TRAP_TEST_DATA_AREA
