# Test SRET by checking mstatus from M-mode afterward
.option norvc

.section .text
.globl _start

_start:
    # Setup trap handler to return to M-mode
    la t0, m_trap_handler
    csrw 0x305, t0    # mtvec

    # Delegate to S-mode
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
    # Clear SPIE
    li t0, 0x20       # SPIE bit 5
    csrc 0x100, t0    # sstatus

    # Read mstatus to save pre-SRET state (store in s0 for later)
    csrr s0, 0x300    # mstatus

    # Execute SRET to return to M-mode (cause an ECALL to trap back)
    la t0, after_sret
    csrw 0x141, t0    # sepc
    sret

after_sret:
    # Read mstatus immediately after SRET (while still in S-mode)
    csrr s1, 0x300    # mstatus after SRET

    # Cause a trap to return to M-mode
    ecall

m_trap_handler:
    # Now in M-mode, s1 already has mstatus from after SRET

    # Extract SPIE (bit 5)
    srli t0, s1, 5
    andi t0, t0, 1

    # Store result
    mv x28, t0        # x28 = SPIE bit (should be 1)
    mv x29, s1        # x29 = full mstatus

    # If SPIE=1, pass
    li t1, 1
    beq t0, t1, pass

fail:
    li x28, 0xDEADBEEF
    ebreak

pass:
    li x28, 0x600DF00D
    ebreak
