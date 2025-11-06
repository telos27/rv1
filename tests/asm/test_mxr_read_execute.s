# ==============================================================================
# Test: MXR (Make eXecutable Readable) - Read from Execute-Only Pages
# ==============================================================================
#
# This test verifies that when MSTATUS.MXR = 1, S-mode can read from
# execute-only pages (pages with X=1, R=0).
#
# Test Sequence:
# 1. Setup page table with X=1, R=0 page (execute-only, not readable)
# 2. Write data to that page from M-mode (M-mode ignores permission bits)
# 3. Enter S-mode with MXR=0 (disabled)
# 4. Try to read from X-only page (should trigger load page fault, code 13)
# 5. Trap handler verifies correct exception
# 6. Set MXR=1 (enabled)
# 7. Try to read from X-only page (should succeed with MXR=1)
# 8. Test passes if both behaviors are correct
#
# IMPORTANT: This feature allows OS kernels to read instruction pages
# (e.g., for instruction emulation, debugging, or code inspection).
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
    # Setup page table with X=1, R=0 (execute-only) page
    ###########################################################################

    # Create a 2-level page table (Sv32)
    # Level 1 (root): Points to level 0 page table
    # Level 0: Contains entry for test page at VA 0x00010000

    # L1 entry 0: Points to L0 page table for VA range 0x00000000-0x003FFFFF
    # PTE format: [31:10] = PPN[1:0], [7:0] = flags
    # Flags: V=1, no leaf (points to next level)
    la      t0, page_table_l0
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field position
    ori     t0, t0, 0x01            # V=1 (valid, non-leaf)
    la      t1, page_table_l1
    sw      t0, 0(t1)               # L1[0] = L0 page table address

    # L0 entry for VA 0x00010000 (VPN[0] = 0x10):
    # Map to physical page containing exec_only_data
    # Flags: V=1, R=0, W=0, X=1, U=0 (supervisor), A=1, D=1
    # Permission: V|X|A|D = 0x01|0x08|0x40|0x80 = 0xC9
    la      t0, exec_only_data
    srli    t0, t0, 12              # Get PPN
    slli    t0, t0, 10              # Shift to PPN field
    ori     t0, t0, 0xC9            # V|X|A|D (no R, no W, yes X)
    la      t1, page_table_l0
    sw      t0, (0x10 * 4)(t1)      # L0[0x10] for VA 0x00010000

    # Enable paging with SATP
    # SATP format: MODE[31]=1 (Sv32), ASID[30:22]=0, PPN[21:0]=root_ppn
    la      t0, page_table_l1
    srli    t0, t0, 12              # Get PPN of root page table
    li      t1, 0x80000000          # MODE = 1 (Sv32)
    or      t0, t0, t1
    csrw    satp, t0
    sfence.vma                      # Flush TLB

    TEST_STAGE 2

    ###########################################################################
    # M-mode: Write test data to X=1,R=0 page (should work - M-mode ignores perms)
    ###########################################################################

    li      t0, 0x45584543          # Test value (0x45584543 = "EXEC" in ASCII)
    li      t1, 0x00010000          # VA of execute-only page
    sw      t0, 0(t1)               # Should work in M-mode
    lw      t2, 0(t1)               # Read back
    bne     t0, t2, test_fail       # Verify write succeeded

    TEST_STAGE 3

    ###########################################################################
    # Setup trap handler to expect page fault (when MXR=0)
    ###########################################################################

    # Set flag to indicate we're expecting a fault
    la      t0, expect_fault_flag
    li      t1, 1
    sw      t1, 0(t0)

    # Save the expected exception cause (will be checked in handler)
    la      t0, expected_cause
    li      t1, CAUSE_LOAD_PAGE_FAULT
    sw      t1, 0(t0)

    TEST_STAGE 4

    ###########################################################################
    # Enter S-mode with MXR=0 (disabled)
    ###########################################################################

    # Ensure MXR bit is 0
    li      t0, MSTATUS_MXR
    csrrc   zero, mstatus, t0       # Clear MXR

    # Delegate page faults to S-mode so we can test S-mode trap handling
    DELEGATE_EXCEPTION CAUSE_LOAD_PAGE_FAULT

    # Enter S-mode
    ENTER_SMODE_M smode_code

smode_code:
    TEST_STAGE 5

    ###########################################################################
    # S-mode test 1: Try to READ from X=1,R=0 page with MXR=0 (should fault)
    ###########################################################################

try_load_mxr0:
    li      t1, 0x00010000          # VA of execute-only page
    lw      t2, 0(t1)               # This should trigger load page fault!

    # If we get here, something is wrong - should have faulted
    j       test_fail

after_load_fault_mxr0:
    TEST_STAGE 6

    ###########################################################################
    # S-mode test 2: Enable MXR and try to READ (should succeed)
    ###########################################################################

    # Clear fault expectation flag
    la      t0, expect_fault_flag
    sw      zero, 0(t0)

    # Enable MXR bit in MSTATUS (via SSTATUS)
    # Note: MXR is accessible in SSTATUS (bit 19 same as MSTATUS)
    li      t0, MSTATUS_MXR
    csrrs   zero, sstatus, t0       # Set MXR via SSTATUS

    # Verify MXR is set
    csrr    t1, sstatus
    li      t2, MSTATUS_MXR
    and     t3, t1, t2
    beqz    t3, test_fail           # MXR should be set

try_load_mxr1:
    li      t1, 0x00010000          # VA of execute-only page
    lw      t2, 0(t1)               # This should SUCCEED with MXR=1

    # Verify we got the correct data
    li      t0, 0x45584543          # 0xEXEC0123
    bne     t2, t0, test_fail       # Data should match

    TEST_STAGE 7

    ###########################################################################
    # All tests passed!
    ###########################################################################

    TEST_PASS

test_fail:
    TEST_FAIL

###############################################################################
# Trap handlers
###############################################################################

# S-mode trap handler
s_trap_handler:
    # Check if we expected a fault
    la      t0, expect_fault_flag
    lw      t1, 0(t0)
    beqz    t1, unexpected_fault    # If not expecting fault, fail

    # Check if the exception cause is correct
    csrr    t2, scause
    la      t0, expected_cause
    lw      t3, 0(t0)
    bne     t2, t3, wrong_cause     # If wrong cause, fail

    # Fault was expected and correct - return to appropriate handler
    csrr    t0, scause
    li      t1, CAUSE_LOAD_PAGE_FAULT
    beq     t0, t1, handle_load_fault

    # Unknown fault type
    j       test_fail

handle_load_fault:
    # Return to code after the faulting load
    # We need to skip the load instruction (4 bytes)
    csrr    t0, sepc
    addi    t0, t0, 4               # Skip faulting instruction
    csrw    sepc, t0

    # Return to after_load_fault_mxr0
    sret

unexpected_fault:
    # We got a fault when we shouldn't have
    j       test_fail

wrong_cause:
    # We got a fault but with wrong exception code
    j       test_fail

# M-mode trap handler (should not be reached - exceptions delegated to S-mode)
m_trap_handler:
    # Save diagnostic info
    csrr    a0, mcause
    csrr    a1, mepc
    csrr    a2, mtval
    # M-mode trap is unexpected
    TEST_FAIL

###############################################################################
# Data section
###############################################################################
.section .data

# Test control variables
.align 4
expect_fault_flag:
    .word 0

# Standard trap test data area
TRAP_TEST_DATA_AREA

# Page tables (4KB aligned)
.align 12
page_table_l1:
    .space 4096

.align 12
page_table_l0:
    .space 4096

# Execute-only test data area (4KB aligned for page mapping)
.align 12
exec_only_data:
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000
    .word 0x00000000
    .space 4080                     # Rest of page
