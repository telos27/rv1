# Test: CSR Side Effects Verification
# Purpose: Verify CSR writes have expected side effects on related CSRs
#
# Tests:
# 1. Writing mstatus affects sstatus (sstatus is a view of mstatus)
# 2. Writing sstatus affects mstatus (for S-mode visible fields)
# 3. Writing mie affects sie (sie is a subset of mie)
# 4. Writing mip affects sip (sip is a subset of mip)
#
# Expected: Changes propagate correctly between related CSRs

.section .text
.globl _start

# CSR addresses
.equ CSR_MSTATUS,   0x300
.equ CSR_SSTATUS,   0x100
.equ CSR_MIE,       0x304
.equ CSR_SIE,       0x104
.equ CSR_MIP,       0x344
.equ CSR_SIP,       0x144

# Status bits
.equ MSTATUS_SIE_BIT,  1
.equ MSTATUS_SIE_MASK, 0x0002

# Interrupt enable bits
.equ MIE_SSIE_BIT,  1
.equ MIE_STIE_BIT,  5
.equ MIE_SEIE_BIT,  9
.equ MIE_MSIE_BIT,  3
.equ MIE_MTIE_BIT,  7
.equ MIE_MEIE_BIT,  11

# Test markers
.equ TEST_PASS_MARKER, 0x600DCAFE
.equ TEST_FAIL_MARKER, 0xDEADDEAD

_start:
    # Initialize test stage counter
    li s0, 1

    #========================================
    # Stage 1: mstatus write affects sstatus
    #========================================
stage_1:
    li s0, 1

    # Clear SIE bit via mstatus
    csrr t0, CSR_MSTATUS
    li t1, MSTATUS_SIE_MASK
    not t1, t1
    and t0, t0, t1
    csrw CSR_MSTATUS, t0

    # Read sstatus and verify SIE is clear
    csrr t2, CSR_SSTATUS
    li t1, MSTATUS_SIE_MASK
    and t3, t2, t1
    bnez t3, test_fail

    # Set SIE bit via mstatus
    csrr t0, CSR_MSTATUS
    li t1, MSTATUS_SIE_MASK
    or t0, t0, t1
    csrw CSR_MSTATUS, t0

    # Read sstatus and verify SIE is set
    csrr t2, CSR_SSTATUS
    li t1, MSTATUS_SIE_MASK
    and t3, t2, t1
    beqz t3, test_fail

    #========================================
    # Stage 2: sstatus write affects mstatus
    #========================================
stage_2:
    li s0, 2

    # Clear SIE bit via sstatus
    csrr t0, CSR_SSTATUS
    li t1, MSTATUS_SIE_MASK
    not t1, t1
    and t0, t0, t1
    csrw CSR_SSTATUS, t0

    # Read mstatus and verify SIE is clear
    csrr t2, CSR_MSTATUS
    li t1, MSTATUS_SIE_MASK
    and t3, t2, t1
    bnez t3, test_fail

    # Set SIE bit via sstatus
    csrr t0, CSR_SSTATUS
    li t1, MSTATUS_SIE_MASK
    or t0, t0, t1
    csrw CSR_SSTATUS, t0

    # Read mstatus and verify SIE is set
    csrr t2, CSR_MSTATUS
    li t1, MSTATUS_SIE_MASK
    and t3, t2, t1
    beqz t3, test_fail

    #========================================
    # Stage 3: mie write affects sie
    #========================================
stage_3:
    li s0, 3

    # Set SSIE bit via mie
    li t1, (1 << MIE_SSIE_BIT)
    csrw CSR_MIE, t1

    # Read sie and verify SSIE is set
    csrr t2, CSR_SIE
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    beqz t3, test_fail

    # Clear mie
    csrw CSR_MIE, zero

    # Read sie and verify it's clear
    csrr t2, CSR_SIE
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    bnez t3, test_fail

    #========================================
    # Stage 4: mip write affects sip
    #========================================
stage_4:
    li s0, 4

    # Set SSIP bit via mip
    li t1, (1 << MIE_SSIE_BIT)
    csrw CSR_MIP, t1

    # Read sip and verify SSIP is set
    csrr t2, CSR_SIP
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    beqz t3, test_fail

    # Clear mip
    csrw CSR_MIP, zero

    # Read sip and verify it's clear
    csrr t2, CSR_SIP
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    bnez t3, test_fail

    #========================================
    # Stage 5: sie write affects mie (for S-mode bits only)
    #========================================
stage_5:
    li s0, 5

    # Clear mie
    csrw CSR_MIE, zero

    # Set SSIE via sie
    li t1, (1 << MIE_SSIE_BIT)
    csrw CSR_SIE, t1

    # Read mie and verify SSIE is set
    csrr t2, CSR_MIE
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    beqz t3, test_fail

    #========================================
    # Stage 6: sip write affects mip (for S-mode bits only)
    #========================================
stage_6:
    li s0, 6

    # Clear mip
    csrw CSR_MIP, zero

    # Set SSIP via sip
    li t1, (1 << MIE_SSIE_BIT)
    csrw CSR_SIP, t1

    # Read mip and verify SSIP is set
    csrr t2, CSR_MIP
    li t1, (1 << MIE_SSIE_BIT)
    and t3, t2, t1
    beqz t3, test_fail

    #========================================
    # All tests passed
    #========================================
test_pass:
    li x28, TEST_PASS_MARKER
    ebreak

    #========================================
    # Test failed
    #========================================
test_fail:
    li x28, TEST_FAIL_MARKER
    ebreak

.section .data
# No data needed
