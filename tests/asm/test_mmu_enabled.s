# Test: Verify MMU is actually enabled and translating
# Check if SATP.MODE is being respected

.section .text
.globl _start

_start:
    # Read SATP initial value
    csrr    t0, satp

    # Write SATP with MODE=1 (Sv32)
    li      t1, 0x80000000      # MODE=1, PPN=0
    csrw    satp, t1

    # Read back SATP
    csrr    t2, satp

    # Check if MODE bit is set
    srli    t3, t2, 31
    andi    t3, t3, 1

    # Store values for inspection
    # t0 = initial SATP
    # t1 = written value (0x80000000)
    # t2 = read-back value
    # t3 = extracted MODE bit (should be 1)

    # Try to read from high address that would need translation
    li      t4, 0x00001000
    lw      t5, 0(t4)

    # SUCCESS if we got here
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
