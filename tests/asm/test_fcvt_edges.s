# Test FCVT.S.W Edge Cases
# Tests INT_MIN, INT_MAX, and powers of 2 conversions

.section .text
.globl _start

_start:
    # Initialize test counter
    li x31, 0

    #===========================================
    # Test 1: INT32_MAX (0x7FFFFFFF = 2147483647)
    #===========================================
    li x5, 0x7FFFFFFF
    fcvt.s.w f5, x5
    fmv.x.w a0, f5
    # Expected: 0x4F000000 (2147483648.0, rounded up due to precision loss)
    li x6, 0x4F000000
    bne a0, x6, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 2: INT32_MIN (0x80000000 = -2147483648)
    #===========================================
    li x7, 0x80000000
    fcvt.s.w f6, x7
    fmv.x.w a1, f6
    # Expected: 0xCF000000 (-2147483648.0)
    li x8, 0xCF000000
    bne a1, x8, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 3: Power of 2 - 4
    #===========================================
    li x9, 4
    fcvt.s.w f7, x9
    fmv.x.w a2, f7
    # Expected: 0x40800000 (4.0)
    li x10, 0x40800000
    bne a2, x10, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 4: Power of 2 - 8
    #===========================================
    li x11, 8
    fcvt.s.w f8, x11
    fmv.x.w a3, f8
    # Expected: 0x41000000 (8.0)
    li x12, 0x41000000
    bne a3, x12, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 5: Power of 2 - 16
    #===========================================
    li x13, 16
    fcvt.s.w f9, x13
    fmv.x.w a4, f9
    # Expected: 0x41800000 (16.0)
    li x14, 0x41800000
    bne a4, x14, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 6: Power of 2 - 32
    #===========================================
    li x15, 32
    fcvt.s.w f10, x15
    fmv.x.w a5, f10
    # Expected: 0x42000000 (32.0)
    li x16, 0x42000000
    bne a5, x16, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 7: Power of 2 - 64
    #===========================================
    li x17, 64
    fcvt.s.w f11, x17
    fmv.x.w a6, f11
    # Expected: 0x42800000 (64.0)
    li x18, 0x42800000
    bne a6, x18, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 8: Power of 2 - 256
    #===========================================
    li x19, 256
    fcvt.s.w f12, x19
    fmv.x.w a7, f12
    # Expected: 0x43800000 (256.0)
    li x20, 0x43800000
    bne a7, x20, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 9: Power of 2 - 1024
    #===========================================
    li x21, 1024
    fcvt.s.w f13, x21
    fmv.x.w t0, f13
    # Expected: 0x44800000 (1024.0)
    li x22, 0x44800000
    bne t0, x22, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 10: Large negative power of 2 - (-1024)
    #===========================================
    li x23, -1024
    fcvt.s.w f14, x23
    fmv.x.w t1, f14
    # Expected: 0xC4800000 (-1024.0)
    li x24, 0xC4800000
    bne t1, x24, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 11: Large value - 1000000
    #===========================================
    li x25, 1000000
    fcvt.s.w f15, x25
    fmv.x.w t2, f15
    # Expected: 0x49742400 (1000000.0)
    li x26, 0x49742400
    bne t2, x26, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 12: Large negative - (-1000000)
    #===========================================
    li x27, -1000000
    fcvt.s.w f16, x27
    fmv.x.w t3, f16
    # Expected: 0xC9742400 (-1000000.0)
    li x28, 0xC9742400
    bne t3, x28, test_failed
    addi x31, x31, 1

    # All tests passed!
    j test_passed

test_failed:
    # Set failure indicator
    li x30, 0xDEADBEEF
    ebreak

test_passed:
    # Set success indicator (should have 12 passed tests)
    li x30, 0x600DCAFE
    # x31 should contain 12
    ebreak
