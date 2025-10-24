# Test SRET SPIE without any CSR reads after SRET
.option norvc

.section .text
.globl _start

_start:
    # Delegate
    li t0, 0xFFFF
    csrw 0x302, t0    # medeleg
    csrw 0x303, t0    # mideleg

    # Enter S-mode
    li t0, 0x880      # MPP=01, MPIE=1
    csrw 0x300, t0    # mstatus
    la t0, smode_code
    csrw 0x341, t0    # mepc
    mret

smode_code:
    # Clear SPIE and SIE
    li t0, 0x22
    csrc 0x100, t0    # sstatus

    # Set SPP=S
    li t0, 0x100
    csrs 0x100, t0    # sstatus

    # Set sepc
    la t0, after_sret
    csrw 0x141, t0    # sepc

    # Execute SRET
    sret

after_sret:
    # DON'T read any CSR here - just do some NOPs and arithmetic
    nop
    nop
    nop

    # Do some arithmetic to let things settle
    li t0, 42
    addi t0, t0, 1
    nop

    # NOW read sstatus (many cycles after SRET)
    csrr t2, 0x100

    # Check SPIE (bit 5)
    andi t3, t2, 0x20
    bnez t3, pass

fail:
    li x28, 0xDEADBEEF
    mv x29, t2
    ebreak

pass:
    li x28, 0x600DF00D
    mv x29, t2
    ebreak
