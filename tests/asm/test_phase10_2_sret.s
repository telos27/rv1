# Test: Phase 10.2 - SRET Instruction
# Comprehensive test for SRET (Supervisor Return)
#
# Tests:
# 1. SRET restores PC from SEPC
# 2. SRET restores privilege from MSTATUS.SPP
# 3. SRET restores interrupt enable: SIE = SPIE, SPIE = 1, SPP = 0

.section .text
.globl _start

_start:
    li      t6, 0             # Test counter

# ============================================================================
# Test 1: SRET restores PC from SEPC
# ============================================================================
test1_sret_pc:
    addi    t6, t6, 1         # Test 1

    # Set SEPC to target address
    la      t0, sret_target1
    csrw    sepc, t0

    # Set SPP = 0 (will return to U-mode, but we're testing PC restore)
    csrr    t0, mstatus
    li      t1, 0xFFFFFEFF    # Clear SPP (bit 8)
    and     t0, t0, t1
    csrw    mstatus, t0

    # Execute SRET
    sret

    # Should not reach here
    j       test_fail

sret_target1:
    # We should land here after SRET
    # Verify by setting marker
    li      t1, 0xAAAA0001
    j       test2_sret_sie

# ============================================================================
# Test 2: SRET restores SIE from SPIE
# ============================================================================
test2_sret_sie:
    addi    t6, t6, 1         # Test 2

    # Set MSTATUS: SIE=0, SPIE=1, SPP=1 (will return to S-mode)
    csrr    t0, mstatus
    # Clear SIE (bit 1), SPP (bit 8)
    li      t1, 0xFFFFFEFD
    and     t0, t0, t1
    # Set SPIE (bit 5), SPP (bit 8) = S-mode
    li      t1, 0x00000120    # SPIE=1, SPP=1
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set SEPC to target
    la      t0, sret_target2
    csrw    sepc, t0

    # Execute SRET
    sret

    # Should not reach here
    j       test_fail

sret_target2:
    # After SRET, verify MSTATUS changes:
    # - SIE should = old SPIE (1)
    # - SPIE should = 1
    # - SPP should = 0
    csrr    t0, mstatus
    andi    t1, t0, 0x00000002  # Extract SIE (bit 1)
    beq     t1, zero, test_fail # SIE should be 1

    andi    t1, t0, 0x00000020  # Extract SPIE (bit 5)
    beq     t1, zero, test_fail # SPIE should be 1

    andi    t1, t0, 0x00000100  # Extract SPP (bit 8)
    bne     t1, zero, test_fail # SPP should be 0

    li      t2, 0xBBBB0002
    j       test3_sret_spie_clear

# ============================================================================
# Test 3: SRET with SPIE=0
# ============================================================================
test3_sret_spie_clear:
    addi    t6, t6, 1         # Test 3

    # Set MSTATUS: SIE=1, SPIE=0, SPP=1
    csrr    t0, mstatus
    # Clear SPIE (bit 5), SPP (bit 8)
    li      t1, 0xFFFFFEDF
    and     t0, t0, t1
    # Set SIE (bit 1), SPP (bit 8)
    li      t1, 0x00000102    # SIE=1, SPP=1
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set SEPC
    la      t0, sret_target3
    csrw    sepc, t0

    # Execute SRET
    sret

    j       test_fail

sret_target3:
    # After SRET with SPIE=0:
    # - SIE should = old SPIE (0)
    # - SPIE should = 1
    # - SPP should = 0
    csrr    t0, mstatus
    andi    t1, t0, 0x00000002  # Extract SIE
    bne     t1, zero, test_fail # SIE should be 0

    andi    t1, t0, 0x00000020  # Extract SPIE
    beq     t1, zero, test_fail # SPIE should be 1

    andi    t1, t0, 0x00000100  # Extract SPP
    bne     t1, zero, test_fail # SPP should be 0

    li      t3, 0xCCCC0003
    j       test4_sret_from_smode

# ============================================================================
# Test 4: SRET from S-mode to U-mode
# ============================================================================
test4_sret_from_smode:
    addi    t6, t6, 1         # Test 4

    # Enter S-mode first via MRET
    # Set MSTATUS.MPP = 01 (S-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFE7FF    # Clear MPP
    and     t0, t0, t1
    li      t1, 0x00000800    # MPP = 01 (S-mode)
    or      t0, t0, t1
    csrw    mstatus, t0

    # Set MEPC to S-mode code
    la      t0, in_smode
    csrw    mepc, t0

    # Save current privilege for verification
    li      s1, 0x11          # M-mode marker

    # Jump to S-mode
    mret

in_smode:
    # We're now in S-mode (privilege = 01)
    li      s1, 0x01          # S-mode marker

    # Set up SRET to return to U-mode
    # Set MSTATUS.SPP = 0 (U-mode)
    csrr    t0, mstatus
    li      t1, 0xFFFFFEFF    # Clear SPP
    and     t0, t0, t1
    csrw    mstatus, t0

    # Set SEPC to U-mode code
    la      t0, after_smode
    csrw    sepc, t0

    # Execute SRET to U-mode
    sret

after_smode:
    # We should be in U-mode now (privilege = 00)
    # We can't directly check privilege, but we executed SRET successfully
    li      s1, 0x00          # U-mode marker (conceptual)
    li      t4, 0xDDDD0004
    j       test_pass

# ============================================================================
# SUCCESS
# ============================================================================
test_pass:
    li      a0, 1             # Success
    li      a1, 4             # Number of tests passed
    mv      a2, t6            # Test counter
    li      t5, 0xDEADBEEF    # Success marker
    ebreak

# ============================================================================
# FAILURE
# ============================================================================
test_fail:
    li      a0, 0             # Failure
    mv      a1, t6            # Failed test number
    ebreak

.align 4
