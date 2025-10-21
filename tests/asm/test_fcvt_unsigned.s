# Test FCVT.S.WU (Unsigned Integer → Float)
# Critical: Unsigned treats 0x80000000 as 2147483648, NOT -2147483648
# Critical: Unsigned treats 0xFFFFFFFF as 4294967295, NOT -1

.section .text
.globl _start

_start:
    # Initialize test counter
    li x31, 0

    #===========================================
    # Test 1: Zero (same for signed/unsigned)
    #===========================================
    li x5, 0
    fcvt.s.wu f5, x5
    fmv.x.w a0, f5
    # Expected: 0x00000000 (0.0)
    li x6, 0x00000000
    bne a0, x6, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 2: Small positive (1)
    #===========================================
    li x7, 1
    fcvt.s.wu f6, x7
    fmv.x.w a1, f6
    # Expected: 0x3F800000 (1.0)
    li x8, 0x3F800000
    bne a1, x8, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 3: 0x80000000 - CRITICAL DIFFERENCE!
    # Signed: -2147483648 → 0xCF000000 (-2147483648.0)
    # Unsigned: 2147483648 → 0x4F000000 (2147483648.0)
    #===========================================
    li x9, 0x80000000
    fcvt.s.wu f7, x9
    fmv.x.w a2, f7
    # Expected: 0x4F000000 (2147483648.0, NOT negative!)
    li x10, 0x4F000000
    bne a2, x10, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 4: 0xFFFFFFFF - CRITICAL DIFFERENCE!
    # Signed: -1 → 0xBF800000 (-1.0)
    # Unsigned: 4294967295 → 0x4F800000 (4294967296.0, rounded)
    #===========================================
    li x11, 0xFFFFFFFF
    fcvt.s.wu f8, x11
    fmv.x.w a3, f8
    # Expected: 0x4F800000 (4294967296.0, rounded to nearest even)
    li x12, 0x4F800000
    bne a3, x12, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 5: 0x7FFFFFFF (INT_MAX = UINT_MAX/2)
    # Should be same as signed for this value
    #===========================================
    li x13, 0x7FFFFFFF
    fcvt.s.wu f9, x13
    fmv.x.w a4, f9
    # Expected: 0x4F000000 (2147483648.0, rounded)
    li x14, 0x4F000000
    bne a4, x14, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 6: Large unsigned - 0x80000001
    # Unsigned: 2147483649 → 0x4F000000 (2147483648.0, rounded down)
    #===========================================
    li x15, 0x80000001
    fcvt.s.wu f10, x15
    fmv.x.w a5, f10
    # Expected: 0x4F000000 (2147483648.0, round to even)
    li x16, 0x4F000000
    bne a5, x16, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 7: 0xFFFFFFFE
    # Unsigned: 4294967294 → 0x4F800000 (4294967296.0, rounded)
    #===========================================
    li x17, 0xFFFFFFFE
    fcvt.s.wu f11, x17
    fmv.x.w a6, f11
    # Expected: 0x4F800000 (4294967296.0)
    li x18, 0x4F800000
    bne a6, x18, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 8: 0xC0000000
    # Unsigned: 3221225472 → 0x4F400000 (3221225472.0)
    #===========================================
    li x19, 0xC0000000
    fcvt.s.wu f12, x19
    fmv.x.w a7, f12
    # Expected: 0x4F400000 (3221225472.0)
    li x20, 0x4F400000
    bne a7, x20, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 9: Small unsigned power of 2 - 256
    #===========================================
    li x21, 256
    fcvt.s.wu f13, x21
    fmv.x.w t0, f13
    # Expected: 0x43800000 (256.0)
    li x22, 0x43800000
    bne t0, x22, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 10: 0x12345678
    # Unsigned: 305419896 → 0x4D91A2B4 (305419904.0, rounded)
    #===========================================
    li x23, 0x12345678
    fcvt.s.wu f14, x23
    fmv.x.w t1, f14
    # Expected: 0x4D91A2B4 (305419904.0)
    li x24, 0x4D91A2B4
    bne t1, x24, test_failed
    addi x31, x31, 1

    # All tests passed!
    j test_passed

test_failed:
    # Set failure indicator
    li x30, 0xDEADBEEF
    # x31 shows which test failed (0-based, so test N failed if x31 = N)
    ebreak

test_passed:
    # Set success indicator (should have 10 passed tests)
    li x30, 0x600DCAFE
    # x31 should contain 10
    ebreak
