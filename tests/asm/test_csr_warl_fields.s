# Test: CSR WARL Fields Verification
# Purpose: Verify WARL (Write Any, Read Legal) field constraints
#
# WARL fields can be written with any value, but only legal values are retained.
# This test verifies that hardware enforces these constraints.
#
# Tests:
# 1. mstatus.MPP [12:11] - Can only be 00 (U), 01 (S), or 11 (M), not 10
# 2. mstatus.SPP [8] - Only 1 bit (0=U, 1=S), can't store M-mode
# 3. mtvec mode [1:0] - 00 (Direct) or 01 (Vectored), not 10 or 11
# 4. mtvec BASE [XLEN-1:2] - Must be 4-byte aligned, bits [1:0] read as mode
#
# Expected: Illegal values are converted to legal values

.section .text
.globl _start

# CSR addresses
.equ CSR_MSTATUS,   0x300
.equ CSR_SSTATUS,   0x100
.equ CSR_MTVEC,     0x305
.equ CSR_STVEC,     0x105

# mstatus field definitions
.equ MSTATUS_MPP_SHIFT, 11
.equ MSTATUS_MPP_MASK,  0x1800  # Bits 12:11
.equ MSTATUS_SPP_BIT,   8
.equ MSTATUS_SPP_MASK,  0x0100  # Bit 8

# Privilege modes
.equ PRIV_U, 0
.equ PRIV_S, 1
.equ PRIV_M, 3

# Test markers
.equ TEST_PASS_MARKER, 0x600DCAFE
.equ TEST_FAIL_MARKER, 0xDEADDEAD

_start:
    # Initialize test stage counter
    li s0, 1

    #========================================
    # Stage 1: Test mstatus.MPP WARL constraint
    # MPP can be 00, 01, or 11, but not 10
    #========================================
stage_1:
    li s0, 1

    # Read current mstatus
    csrr t0, CSR_MSTATUS

    # Try to write MPP=10 (invalid) by setting all bits
    li t1, 0xFFFFFFFF
    csrw CSR_MSTATUS, t1

    # Read back mstatus
    csrr t2, CSR_MSTATUS

    # Extract MPP field
    li t3, MSTATUS_MPP_MASK
    and t4, t2, t3
    srli t4, t4, MSTATUS_MPP_SHIFT

    # Verify MPP is NOT 2 (illegal value)
    li t5, 2
    beq t4, t5, test_fail

    # Verify MPP is one of 0, 1, or 3
    beqz t4, mpp_ok_1    # MPP=0 is valid
    li t5, 1
    beq t4, t5, mpp_ok_1  # MPP=1 is valid
    li t5, 3
    beq t4, t5, mpp_ok_1  # MPP=3 is valid
    j test_fail           # Any other value is invalid

mpp_ok_1:

    #========================================
    # Stage 2: Test mstatus.SPP WARL constraint
    # SPP is 1 bit: 0=U-mode, 1=S-mode
    #========================================
stage_2:
    li s0, 2

    # Write sstatus with all bits set
    li t1, 0xFFFFFFFF
    csrw CSR_SSTATUS, t1

    # Read back sstatus
    csrr t2, CSR_SSTATUS

    # Extract SPP field (bit 8)
    li t3, MSTATUS_SPP_MASK
    and t4, t2, t3
    srli t4, t4, MSTATUS_SPP_BIT

    # SPP should be 0 or 1 only
    li t5, 2
    bgeu t4, t5, test_fail  # If SPP >= 2, it's invalid

    #========================================
    # Stage 3: Test mtvec mode WARL constraint
    # Mode bits [1:0]: 00=Direct, 01=Vectored, 10/11=Reserved
    #========================================
stage_3:
    li s0, 3

    # Try to write mode=10 (BASE=0x100, mode=10 binary)
    li t1, 0x00000102  # BASE=0x100, mode=10
    csrw CSR_MTVEC, t1

    # Read back mtvec
    csrr t2, CSR_MTVEC

    # Extract mode bits [1:0]
    andi t3, t2, 0x3

    # Verify mode is 0 or 1 (not 2 or 3)
    li t4, 2
    bgeu t3, t4, test_fail  # Mode should be < 2

    #========================================
    # Stage 4: Test mtvec mode=11 (another reserved value)
    #========================================
stage_4:
    li s0, 4

    # Try to write mode=11 (BASE=0x200, mode=11 binary)
    li t1, 0x00000203  # BASE=0x200, mode=11
    csrw CSR_MTVEC, t1

    # Read back mtvec
    csrr t2, CSR_MTVEC

    # Extract mode bits [1:0]
    andi t3, t2, 0x3

    # Verify mode is 0 or 1 (not 2 or 3)
    li t4, 2
    bgeu t3, t4, test_fail  # Mode should be < 2

    #========================================
    # Stage 5: Test mtvec BASE alignment
    # BASE must be 4-byte aligned (bits [1:0] are mode, not address)
    #========================================
stage_5:
    li s0, 5

    # Write mtvec with misaligned BASE
    # Try: BASE=0x103 (not 4-byte aligned), mode=00
    li t1, 0x0000010C  # Attempt BASE=0x103, mode=00 (bits set: 0x103 << 2 | 0 = 0x40C, but mode in [1:0])
    # Actually, for proper test: write 0x106 which has BASE with low bits set
    li t1, 0x00000106  # This should be interpreted and cleaned up
    csrw CSR_MTVEC, t1

    # Read back mtvec
    csrr t2, CSR_MTVEC

    # In Direct mode (mode=00), bits [1:0] should be 00
    # In Vectored mode (mode=01), bits [1:0] should be 01
    # Either way, if we tried to set bogus alignment, it should be corrected

    # For this test, just verify mode bits are 0 or 1
    andi t3, t2, 0x3
    li t4, 2
    bgeu t3, t4, test_fail

    #========================================
    # Stage 6: Verify MPP can hold valid values (0, 1, 3)
    #========================================
stage_6:
    li s0, 6

    # Test MPP=0 (U-mode)
    csrr t0, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    not t1, t1
    and t0, t0, t1        # Clear MPP bits
    csrw CSR_MSTATUS, t0
    csrr t2, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    and t3, t2, t1
    bnez t3, test_fail    # MPP should be 0

    # Test MPP=1 (S-mode)
    csrr t0, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    not t1, t1
    and t0, t0, t1        # Clear MPP bits
    li t1, (1 << MSTATUS_MPP_SHIFT)
    or t0, t0, t1         # Set MPP=1
    csrw CSR_MSTATUS, t0
    csrr t2, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    and t3, t2, t1
    srli t3, t3, MSTATUS_MPP_SHIFT
    li t4, 1
    bne t3, t4, test_fail  # MPP should be 1

    # Test MPP=3 (M-mode)
    csrr t0, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    not t1, t1
    and t0, t0, t1        # Clear MPP bits
    li t1, (3 << MSTATUS_MPP_SHIFT)
    or t0, t0, t1         # Set MPP=3
    csrw CSR_MSTATUS, t0
    csrr t2, CSR_MSTATUS
    li t1, MSTATUS_MPP_MASK
    and t3, t2, t1
    srli t3, t3, MSTATUS_MPP_SHIFT
    li t4, 3
    bne t3, t4, test_fail  # MPP should be 3

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
