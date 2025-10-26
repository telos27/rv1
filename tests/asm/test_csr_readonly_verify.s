# Test: CSR Read-Only Verification (Simplified)
# Purpose: Verify that read-only CSR values are consistent across multiple reads
#
# Note: According to RISC-V spec, writing to read-only CSRs causes illegal
# instruction exceptions. This test only verifies the CSRs are readable and
# return consistent values.
#
# Tests:
# 1. mvendorid (0xF11) - Vendor ID
# 2. marchid (0xF12) - Architecture ID
# 3. mimpid (0xF13) - Implementation ID
# 4. mhartid (0xF14) - Hardware Thread ID
# 5. misa (0x301) - ISA description
#
# Expected: All CSRs return the same value on multiple reads

.section .text
.globl _start

# CSR addresses
.equ CSR_MVENDORID, 0xF11
.equ CSR_MARCHID,   0xF12
.equ CSR_MIMPID,    0xF13
.equ CSR_MHARTID,   0xF14
.equ CSR_MISA,      0x301

# Test markers
.equ TEST_PASS_MARKER, 0x600DCAFE
.equ TEST_FAIL_MARKER, 0xDEADDEAD

_start:
    # Initialize test stage counter
    li s0, 1

    #========================================
    # Stage 1: Test mvendorid (Vendor ID)
    #========================================
stage_1:
    li s0, 1

    # Read mvendorid multiple times
    csrr t0, CSR_MVENDORID
    csrr t1, CSR_MVENDORID
    csrr t2, CSR_MVENDORID

    # Verify all reads returned the same value
    bne t0, t1, test_fail
    bne t0, t2, test_fail

    #========================================
    # Stage 2: Test marchid (Architecture ID)
    #========================================
stage_2:
    li s0, 2

    # Read marchid multiple times
    csrr t0, CSR_MARCHID
    csrr t1, CSR_MARCHID
    csrr t2, CSR_MARCHID

    # Verify all reads returned the same value
    bne t0, t1, test_fail
    bne t0, t2, test_fail

    #========================================
    # Stage 3: Test mimpid (Implementation ID)
    #========================================
stage_3:
    li s0, 3

    # Read mimpid multiple times
    csrr t0, CSR_MIMPID
    csrr t1, CSR_MIMPID
    csrr t2, CSR_MIMPID

    # Verify all reads returned the same value
    bne t0, t1, test_fail
    bne t0, t2, test_fail

    #========================================
    # Stage 4: Test mhartid (Hardware Thread ID)
    #========================================
stage_4:
    li s0, 4

    # Read mhartid multiple times
    csrr t0, CSR_MHARTID
    csrr t1, CSR_MHARTID
    csrr t2, CSR_MHARTID

    # Verify all reads returned the same value
    bne t0, t1, test_fail
    bne t0, t2, test_fail

    #========================================
    # Stage 5: Test misa (ISA description)
    #========================================
stage_5:
    li s0, 5

    # Read misa multiple times
    csrr t0, CSR_MISA
    csrr t1, CSR_MISA
    csrr t2, CSR_MISA

    # Verify all reads returned the same value
    bne t0, t1, test_fail
    bne t0, t2, test_fail

    # Verify misa has expected format
    # Bit 31:30 should indicate MXL (01=32-bit, 10=64-bit)
    srli t3, t0, 30
    li t4, 1  # Expected: 01 for RV32
    bne t3, t4, test_fail

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
