# test_peripheral_mmio.s - Memory-Mapped Peripheral Access Test
# Tests basic read/write to CLINT, UART, and PLIC peripherals
# Author: RV1 Project
# Date: 2025-10-27

.section .text
.globl _start

_start:
    # Initialize test counter
    li      t0, 0           # Test counter

    #==========================================================================
    # Test 1: CLINT MTIME Read (should be non-zero after reset)
    #==========================================================================
test_clint_mtime:
    li      t1, 0x0200BFF8  # MTIME address (64-bit counter)
    lw      t2, 0(t1)       # Read lower 32 bits
    lw      t3, 4(t1)       # Read upper 32 bits

    # MTIME should be > 0 after some cycles
    # For now, just verify read doesn't crash
    addi    t0, t0, 1       # Test 1 passed

    #==========================================================================
    # Test 2: CLINT MTIMECMP Write/Read
    #==========================================================================
test_clint_mtimecmp:
    li      t1, 0x02004000  # MTIMECMP address (hart 0)
    li      t2, 0x12345678  # Test pattern (lower 32 bits)
    li      t3, 0x9ABCDEF0  # Test pattern (upper 32 bits)

    sw      t2, 0(t1)       # Write lower 32 bits
    sw      t3, 4(t1)       # Write upper 32 bits

    lw      t4, 0(t1)       # Read back lower 32 bits
    lw      t5, 4(t1)       # Read back upper 32 bits

    bne     t2, t4, test_fail
    bne     t3, t5, test_fail
    addi    t0, t0, 1       # Test 2 passed

    #==========================================================================
    # Test 3: CLINT MSIP Write/Read (Software Interrupt)
    #==========================================================================
test_clint_msip:
    li      t1, 0x02000000  # MSIP address (hart 0)
    li      t2, 1           # Set MSIP bit

    sw      t2, 0(t1)       # Write MSIP
    lw      t3, 0(t1)       # Read back MSIP

    andi    t3, t3, 1       # Mask to bit 0
    bne     t2, t3, test_fail

    # Clear MSIP
    li      t2, 0
    sw      t2, 0(t1)
    lw      t3, 0(t1)
    andi    t3, t3, 1
    bne     t2, t3, test_fail

    addi    t0, t0, 1       # Test 3 passed

    #==========================================================================
    # Test 4: UART Scratch Register (simplest test)
    #==========================================================================
test_uart_scratch:
    li      t1, 0x10000007  # UART SCR (scratch register) address
    li      t2, 0xAA        # Test pattern

    sb      t2, 0(t1)       # Write scratch register
    lbu     t3, 0(t1)       # Read back

    bne     t2, t3, test_fail
    addi    t0, t0, 1       # Test 4 passed

    #==========================================================================
    # Test 5: UART Line Status Register Read (LSR)
    #==========================================================================
test_uart_lsr:
    li      t1, 0x10000005  # UART LSR address
    lbu     t2, 0(t1)       # Read LSR

    # LSR should have bit 5 (THRE) and bit 6 (TEMT) set after reset
    # (transmitter empty)
    andi    t3, t2, 0x60    # Mask bits 6:5
    li      t4, 0x60        # Expected: both bits set
    bne     t3, t4, test_fail

    addi    t0, t0, 1       # Test 5 passed

    #==========================================================================
    # Test 6: PLIC Priority Register Write/Read
    #==========================================================================
test_plic_priority:
    li      t1, 0x0C000004  # PLIC Priority[1] address (source 1)
    li      t2, 5           # Priority 5

    sw      t2, 0(t1)       # Write priority
    lw      t3, 0(t1)       # Read back

    andi    t3, t3, 7       # Mask to 3 bits (priority 0-7)
    bne     t2, t3, test_fail

    addi    t0, t0, 1       # Test 6 passed

    #==========================================================================
    # Test 7: PLIC Enable Register Write/Read (M-mode)
    #==========================================================================
test_plic_enable:
    li      t1, 0x0C002000  # PLIC M-mode Enable address (hart 0)
    li      t2, 0x0000000A  # Enable sources 1 and 3 (bits 1,3)

    sw      t2, 0(t1)       # Write enable mask
    lw      t3, 0(t1)       # Read back

    bne     t2, t3, test_fail

    addi    t0, t0, 1       # Test 7 passed

    #==========================================================================
    # Test 8: PLIC Threshold Register Write/Read (M-mode)
    #==========================================================================
test_plic_threshold:
    li      t1, 0x0C200000  # PLIC M-mode Threshold address (hart 0)
    li      t2, 3           # Threshold 3

    sw      t2, 0(t1)       # Write threshold
    lw      t3, 0(t1)       # Read back

    andi    t3, t3, 7       # Mask to 3 bits
    bne     t2, t3, test_fail

    addi    t0, t0, 1       # Test 8 passed

    #==========================================================================
    # All Tests Passed
    #==========================================================================
test_pass:
    li      a0, 0           # Return code 0 (success)
    li      a1, 8           # Number of tests passed
    j       test_done

test_fail:
    li      a0, 1           # Return code 1 (failure)
    mv      a1, t0          # Return which test failed
    j       test_done

test_done:
    # Write test result to special address for testbench detection
    li      t1, 0x80001000  # Test completion address
    sw      a0, 0(t1)       # Write result (0=pass, 1=fail)
    sw      a1, 4(t1)       # Write test count/failed test number

    # Infinite loop (testbench will detect completion)
1:  j       1b

.section .data
# No data needed for this test
