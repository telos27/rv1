# Test: CLINT Timer Interrupt
# Purpose: Verify that MTIMECMP writes trigger timer interrupts
# Expected: Timer interrupt fires when mtime >= mtimecmp

.section .text
.globl _start

_start:
    # Initialize stack pointer
    li sp, 0x80100000

    # Setup trap handler
    la t0, trap_handler
    csrw mtvec, t0

    # Read current mtime (lower 32 bits)
    li t0, 0x0200BFF8          # MTIME address
    lw t1, 0(t0)               # Read mtime_lo

    # Set MTIMECMP to mtime + 100 cycles
    li t2, 100
    add t3, t1, t2             # mtimecmp = mtime + 100

    li t0, 0x02004000          # MTIMECMP address (hart 0)
    sw t3, 0(t0)               # Write mtimecmp_lo
    sw zero, 4(t0)             # Write mtimecmp_hi = 0

    # Enable timer interrupt in MIE (bit 7)
    li t0, 0x80                # MTIE = bit 7
    csrs mie, t0

    # Enable global interrupts in MSTATUS (bit 3 = MIE)
    li t0, 0x8
    csrs mstatus, t0

    # Set flag to 0 (interrupt not received)
    li t0, 0x80000100
    sw zero, 0(t0)

    # Wait for interrupt
wait_loop:
    # Check if interrupt flag was set
    li t0, 0x80000100
    lw t1, 0(t0)
    bnez t1, interrupt_received

    # Keep waiting
    j wait_loop

interrupt_received:
    # Success - interrupt was received
    li a0, 0
    j test_end

    .align 2               # Align to 4-byte boundary for MTVEC
trap_handler:
    # Save context
    addi sp, sp, -16
    sw t0, 0(sp)
    sw t1, 4(sp)
    sw t2, 8(sp)
    sw ra, 12(sp)

    # Check if this is a timer interrupt
    csrr t0, mcause
    li t1, 0x80000007          # Timer interrupt cause
    bne t0, t1, not_timer

    # Timer interrupt - set flag
    li t0, 0x80000100
    li t1, 1
    sw t1, 0(t0)

    # Clear timer interrupt by setting mtimecmp to max
    li t0, 0x02004000
    li t1, -1
    sw t1, 0(t0)
    sw t1, 4(t0)

not_timer:
    # Restore context
    lw t0, 0(sp)
    lw t1, 4(sp)
    lw t2, 8(sp)
    lw ra, 12(sp)
    addi sp, sp, 16

    mret

test_end:
    # Write result to test output location
    li t0, 0x80000000
    sw a0, 0(t0)

    # Infinite loop
1:
    j 1b
