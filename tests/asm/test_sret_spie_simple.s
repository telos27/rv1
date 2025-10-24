# Ultra-minimal test to debug SRET SPIE update
# Just set SPIE=0, execute SRET, check if SPIE becomes 1

.option norvc

.section .text
.globl _start

_start:
    # Delegate all traps to S-mode
    li t0, 0xFFFF
    csrw 0x302, t0    # medeleg
    csrw 0x303, t0    # mideleg

    # Enter S-mode from M-mode
    # Set mstatus.MPP = S-mode (01 in bits [12:11])
    li t0, 0x800      # MPP = 01 (S-mode)
    csrs 0x300, t0    # mstatus

    # Set MPIE = 1
    li t0, 0x80       # MPIE bit 7
    csrs 0x300, t0

    # Set mepc to S-mode code
    la t0, smode_code
    csrw 0x341, t0    # mepc

    # Enter S-mode
    mret

smode_code:
    # Now in S-mode

    # Clear both SIE and SPIE
    li t0, 0x22       # Bits 5 (SPIE) and 1 (SIE)
    csrc 0x100, t0    # sstatus

    # Read sstatus to verify they're clear
    csrr t1, 0x100    # sstatus

    # Set SPP = S-mode (bit 8) to stay in S-mode
    li t0, 0x100      # SPP bit 8
    csrs 0x100, t0    # sstatus

    # Set sepc to return address
    la t0, after_sret
    csrw 0x141, t0    # sepc

    # Execute SRET
    sret

after_sret:
    # Add NOP to separate SRET from CSR read
    nop

    # Read sstatus after SRET
    csrr t2, 0x100    # sstatus into t2

    # Check if bit 5 (SPIE) is set
    andi t3, t2, 0x20 # Isolate bit 5
    bnez t3, pass     # If SPIE=1, pass

fail:
    # SPIE was not set - FAIL
    li x28, 0xDEADBEEF
    # Write the actual sstatus value to x29 for debugging
    mv x29, t2
    ebreak

pass:
    # SPIE was set - PASS
    li x28, 0x600DF00D
    # Also store sstatus for verification
    mv x29, t2
    ebreak
