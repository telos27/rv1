# Test: Phase 10.2 - Supervisor Mode CSRs
# Comprehensive test for all S-mode CSRs and trap delegation
# Tests: stvec, sscratch, sepc, scause, stval, medeleg, mideleg, sstatus, sie, sip

.section .text
.globl _start

_start:
    # Initialize test counter
    li      t6, 0             # Test counter (starts at 0)

# ============================================================================
# Test 1: STVEC (Supervisor Trap Vector) - Read/Write
# ============================================================================
test_stvec:
    addi    t6, t6, 1         # Test 1
    li      t0, 0x80001000
    csrw    stvec, t0
    csrr    t1, stvec
    li      t2, 0x80001000    # Expected (4-byte aligned)
    bne     t1, t2, test_fail

# ============================================================================
# Test 2: SSCRATCH (Supervisor Scratch) - Read/Write
# ============================================================================
test_sscratch:
    addi    t6, t6, 1         # Test 2
    li      t0, 0xAAAA5555
    csrw    sscratch, t0
    csrr    t1, sscratch
    bne     t0, t1, test_fail

# ============================================================================
# Test 3: SEPC (Supervisor Exception PC) - Read/Write
# ============================================================================
test_sepc:
    addi    t6, t6, 1         # Test 3
    li      t0, 0x80002000
    csrw    sepc, t0
    csrr    t1, sepc
    li      t2, 0x80002000    # Expected (4-byte aligned)
    bne     t1, t2, test_fail

# ============================================================================
# Test 4: SCAUSE (Supervisor Cause) - Read/Write
# ============================================================================
test_scause:
    addi    t6, t6, 1         # Test 4
    li      t0, 0x0000000F
    csrw    scause, t0
    csrr    t1, scause
    bne     t0, t1, test_fail

# ============================================================================
# Test 5: STVAL (Supervisor Trap Value) - Read/Write
# ============================================================================
test_stval:
    addi    t6, t6, 1         # Test 5
    li      t0, 0xDEADBEEF
    csrw    stval, t0
    csrr    t1, stval
    bne     t0, t1, test_fail

# ============================================================================
# Test 6: MEDELEG (Machine Exception Delegation) - Read/Write
# ============================================================================
test_medeleg:
    addi    t6, t6, 1         # Test 6
    li      t0, 0x0000B1FF    # Delegate common exceptions
    csrw    medeleg, t0
    csrr    t1, medeleg
    bne     t0, t1, test_fail

# ============================================================================
# Test 7: MIDELEG (Machine Interrupt Delegation) - Read/Write
# ============================================================================
test_mideleg:
    addi    t6, t6, 1         # Test 7
    li      t0, 0x00000222    # Delegate S-mode interrupts
    csrw    mideleg, t0
    csrr    t1, mideleg
    bne     t0, t1, test_fail

# ============================================================================
# Test 8: SSTATUS (Supervisor Status) - Subset of MSTATUS
# ============================================================================
test_sstatus:
    addi    t6, t6, 1         # Test 8

    # Clear mstatus first
    csrw    mstatus, zero

    # Write to mstatus - set SIE, SPIE, SPP, SUM, MXR
    li      t0, 0x000C0122    # SUM[18], MXR[19], SPP[8], SPIE[5], SIE[1]
    csrw    mstatus, t0

    # Read sstatus and verify it reflects mstatus S-mode fields
    csrr    t1, sstatus
    li      t2, 0x000C0122    # Should see SUM, MXR, SPP, SPIE, SIE
    bne     t1, t2, test_fail

    # Write to sstatus (should update mstatus)
    li      t0, 0x00000020    # Set only SPIE
    csrw    sstatus, t0
    csrr    t1, mstatus
    li      t3, 0x000C0122      # Mask for S-mode visible bits
    and     t1, t1, t3          # Mask S-mode visible bits
    li      t2, 0x00000020    # Only SPIE should be set
    bne     t1, t2, test_fail

# ============================================================================
# Test 9: SIE (Supervisor Interrupt Enable) - Subset of MIE
# ============================================================================
test_sie:
    addi    t6, t6, 1         # Test 9

    # Clear mie first
    csrw    mie, zero

    # Write to mie - set all interrupt enables
    li      t0, 0x00000FFF
    csrw    mie, t0

    # Read sie - should only see bits [9,5,1] (SEIE, STIE, SSIE)
    csrr    t1, sie
    li      t2, 0x00000222    # Only S-mode interrupt bits
    bne     t1, t2, test_fail

    # Write to sie
    li      t0, 0x00000020    # Set only STIE
    csrw    sie, t0
    csrr    t1, mie
    li      t3, 0x00000222      # Mask for S-mode bits
    and     t1, t1, t3          # Mask S-mode bits
    li      t2, 0x00000020
    bne     t1, t2, test_fail

# ============================================================================
# Test 10: SIP (Supervisor Interrupt Pending) - Subset of MIP
# ============================================================================
test_sip:
    addi    t6, t6, 1         # Test 10

    # Note: SIP is typically read-only from software perspective
    # We'll just verify it reads as subset of MIP
    csrw    mip, zero
    csrr    t1, sip
    bne     t1, zero, test_fail

# ============================================================================
# Test 11: SATP (Supervisor Address Translation) - Read/Write
# ============================================================================
test_satp:
    addi    t6, t6, 1         # Test 11
    li      t0, 0x80000000    # MODE=Sv32, PPN=0
    csrw    satp, t0
    csrr    t1, satp
    bne     t0, t1, test_fail

# ============================================================================
# SUCCESS - All CSR tests passed!
# ============================================================================
test_pass:
    li      a0, 1             # Success code
    li      a1, 11            # Number of tests passed
    mv      t3, t6            # Copy test counter to t3
    ebreak                    # Signal test completion

# ============================================================================
# FAILURE - Test failed
# ============================================================================
test_fail:
    li      a0, 0             # Failure code
    mv      a1, t6            # Failed test number
    ebreak                    # Signal test failure

.align 4
