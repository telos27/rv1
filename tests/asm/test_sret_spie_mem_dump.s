# Test SRET SPIE with memory dumps for inspection
.option norvc

.section .text
.globl _start

_start:
    # Delegate all traps to S-mode
    li t0, 0xFFFF
    csrw 0x302, t0    # medeleg
    csrw 0x303, t0    # mideleg

    # Enter S-mode from M-mode
    li t0, 0x880      # MPP = 01 (S-mode), MPIE = 1
    csrw 0x300, t0    # mstatus

    la t0, smode_code
    csrw 0x341, t0    # mepc
    mret

smode_code:
    # Stage 1: Clear SPIE and SIE
    li t0, 0x22       # Bits 5 (SPIE) and 1 (SIE)
    csrc 0x100, t0    # sstatus - clear both bits

    # Stage 2: Set SPP = S-mode
    li t0, 0x100      # SPP bit 8
    csrs 0x100, t0    # sstatus

    # Read sstatus BEFORE SRET
    csrr t1, 0x100    # sstatus
    li t0, 0x2000
    sw t1, 0(t0)      # Store at 0x2000

    # Also read mstatus from M-mode perspective (need to switch temporarily)
    # Actually, we can't read mstatus from S-mode, so skip this

    # Set sepc
    la t0, after_sret
    csrw 0x141, t0    # sepc

    # Execute SRET
    sret

after_sret:
    # Read sstatus AFTER SRET
    csrr t2, 0x100    # sstatus
    li t0, 0x2004
    sw t2, 0(t0)      # Store at 0x2004

    # Check if SPIE (bit 5) is set
    andi t3, t2, 0x20
    bnez t3, pass

fail:
    li x28, 0xDEADBEEF
    mv x29, t2        # Store sstatus in x29
    ebreak

pass:
    li x28, 0x600DF00D
    mv x29, t2        # Store sstatus in x29
    ebreak
