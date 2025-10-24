# Minimal test: MRET in U-mode should trap
# Expected: Illegal instruction exception (cause=2)

.section .text
.globl _start

_start:
    # Setup trap handler
    la t0, trap_handler
    csrw mtvec, t0

    # Clear MPP to U-mode
    li t1, 0xFFFFE7FF      # Mask to clear MPP bits [12:11]
    csrr t2, mstatus
    and t2, t2, t1
    csrw mstatus, t2        # MPP = 00 (U-mode)

    # Set MEPC to U-mode code
    la t0, umode_code
    csrw mepc, t0

    # Enter U-mode via MRET
    mret

umode_code:
    # Now in U-mode, try to execute MRET (should trap)
    mret

    # Should NOT reach here
    li t0, 0xDEADDEAD
    mv t3, t0
    ebreak

trap_handler:
    # Check if it's illegal instruction (cause=2)
    csrr t0, mcause
    li t1, 2
    bne t0, t1, test_fail

    # SUCCESS!
    li t0, 0xDEADBEEF
    mv t3, t0
    ebreak

test_fail:
    li t0, 0xDEADDEAD
    mv t3, t0
    ebreak
