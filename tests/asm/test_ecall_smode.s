# Test: ECALL from S-mode and Trap Delegation
# Tests:
# 1. ECALL from M-mode (should trap to M-mode)
# 2. ECALL from S-mode (should trap to M-mode or S-mode based on delegation)
# 3. Trap delegation configuration

.section .text
.globl _start

_start:
    ###########################################################################
    # Setup trap vectors
    ###########################################################################
    la      t0, m_trap_vector
    csrw    mtvec, t0

    la      t0, s_trap_vector
    csrw    stvec, t0

    ###########################################################################
    # TEST 1: ECALL from M-mode (no delegation)
    ###########################################################################
    # Clear medeleg to ensure ECALL goes to M-mode
    csrw    medeleg, zero

    # Set marker
    li      s0, 0x11111111

    # Do ECALL from M-mode
    ecall

    # Should return here after trap handler
    li      s1, 0x22222222

    ###########################################################################
    # TEST 2: Enter S-mode and do ECALL (should go to M-mode)
    ###########################################################################
    # Set MPP = S-mode
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF
    and     t0, t0, t1
    li      t1, 0x00000800
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set MEPC to S-mode code
    la      t0, s_mode_test
    csrw    mepc, t0

    # Enter S-mode
    mret

s_mode_test:
    # Now in S-mode
    # Set marker
    li      s2, 0x33333333

    # Do ECALL from S-mode (should go to M-mode handler)
    ecall

    # Should return here
    li      s3, 0x44444444

    # SUCCESS
    j       test_pass

m_trap_vector:
    # M-mode trap handler
    csrr    t0, mcause

    # Check if it's ECALL from M-mode (cause = 11)
    li      t1, 11
    beq     t0, t1, m_ecall_from_m

    # Check if it's ECALL from S-mode (cause = 9)
    li      t1, 9
    beq     t0, t1, m_ecall_from_s

    # Unexpected trap
    j       test_fail

m_ecall_from_m:
    # ECALL from M-mode - advance MEPC past ECALL
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

m_ecall_from_s:
    # ECALL from S-mode - advance MEPC past ECALL
    csrr    t0, mepc
    addi    t0, t0, 4
    csrw    mepc, t0
    mret

s_trap_vector:
    # S-mode trap handler (not used in this test)
    j       test_fail

test_pass:
    li      t0, 0xDEADBEEF
    mv      x28, t0
    nop
    nop
    ebreak

test_fail:
    li      t0, 0xDEADDEAD
    mv      x28, t0
    nop
    nop
    ebreak

.align 4
