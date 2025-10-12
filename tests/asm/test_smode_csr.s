# Test: Supervisor Mode CSR Read/Write
# Simple test to verify S-mode CSRs are accessible

.section .text
.globl _start

_start:
    # Test S-mode CSR writes and reads

    # Test stvec
    li      t0, 0x80001000
    csrw    stvec, t0
    csrr    t1, stvec
    bne     t0, t1, fail

    # Test sscratch
    li      t0, 0xAAAA5555
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, fail

    # Test sepc
    li      t0, 0x80002000
    csrw    sepc, t0
    csrr    t1, sepc
    bne     t0, t1, fail

    # Test scause
    li      t0, 0x0000000F
    csrw    scause, t0
    csrr    t1, scause
    bne     t0, t1, fail

    # Test stval
    li      t0, 0xDEADBEEF
    csrw    stval, t0
    csrr    t1, stval
    bne     t0, t1, fail

    # Test medeleg
    li      t0, 0x0000FFFF
    csrw    medeleg, t0
    csrr    t1, medeleg
    bne     t0, t1, fail

    # Test mideleg
    li      t0, 0x00000AAA
    csrw    mideleg, t0
    csrr    t1, mideleg
    bne     t0, t1, fail

    # Test sstatus (read-only view of mstatus)
    # Write to mstatus and check sstatus reflects it
    li      t0, 0x00000122        # Set MIE, SPIE, SIE bits
    csrw    mstatus, t0
    csrr    t1, sstatus
    andi    t1, t1, 0x00000122
    bne     t0, t1, fail

    # SUCCESS
    li      a0, 1
    ebreak

fail:
    li      a0, 0
    ebreak
