# Simple Timer Interrupt Test
# Tests CLINT timer interrupt delivery to CPU

.section .text
.globl _start

_start:
    # Set up trap handler
    la t0, trap_handler
    csrw mtvec, t0

    # Enable machine interrupts globally
    li t0, 0x8               # MSTATUS.MIE = 1
    csrs mstatus, t0

    # Enable timer interrupt in MIE
    li t0, 0x80              # MIE.MTIE = 1
    csrw mie, t0

    # Read current mtime
    li t0, 0x0200BFF8       # MTIME address
    lw t1, 0(t0)            # Read lower 32 bits

    # Set MTIMECMP = mtime + 100 (interrupt in 100 cycles)
    addi t1, t1, 100
    li t0, 0x02004000       # MTIMECMP address
    sw t1, 0(t0)            # Write lower 32 bits
    sw zero, 4(t0)          # Write upper 32 bits = 0

    # Wait for interrupt
    li a0, 0                # a0 = 0 (not interrupted yet)
wait_loop:
    # Spin here until interrupt fires
    j wait_loop

trap_handler:
    # Interrupt received!
    li a0, 1                # a0 = 1 (success - interrupt fired)

    # Clear interrupt by setting MTIMECMP to max
    li t0, 0x02004000
    li t1, -1
    sw t1, 0(t0)
    sw t1, 4(t0)

    # Return from trap
    mret

# Infinite loop if test passes
test_pass:
    li a0, 42               # Success indicator
    j test_pass
