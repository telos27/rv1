# Test FCVT.W.S and FCVT.WU.S (Float → Integer)
# This tests float to signed/unsigned integer conversions
# Default rounding mode: RNE (Round to Nearest, ties to Even)

.section .text
.globl _start

_start:
    # Initialize test counter
    li x31, 0

    #===========================================
    # FCVT.W.S Tests (Float → Signed Int)
    #===========================================

    #===========================================
    # Test 1: 0.0 → 0
    #===========================================
    li x5, 0x00000000          # +0.0
    fmv.w.x f5, x5
    fcvt.w.s x6, f5
    li x7, 0
    bne x6, x7, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 2: 1.0 → 1
    #===========================================
    li x8, 0x3F800000          # 1.0
    fmv.w.x f6, x8
    fcvt.w.s x9, f6
    li x10, 1
    bne x9, x10, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 3: -1.0 → -1 (0xFFFFFFFF)
    #===========================================
    li x11, 0xBF800000         # -1.0
    fmv.w.x f7, x11
    fcvt.w.s x12, f7
    li x13, -1                 # 0xFFFFFFFF
    bne x12, x13, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 4: 1.5 → 2 (round to nearest even)
    #===========================================
    li x14, 0x3FC00000         # 1.5
    fmv.w.x f8, x14
    fcvt.w.s x15, f8
    li x16, 2
    bne x15, x16, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 5: 2.5 → 2 (round to nearest even, ties to even)
    #===========================================
    li x17, 0x40200000         # 2.5
    fmv.w.x f9, x17
    fcvt.w.s x18, f9
    li x19, 2                  # Rounds to 2 (even)
    bne x18, x19, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 6: 3.5 → 4 (round to nearest even)
    #===========================================
    li x20, 0x40600000         # 3.5
    fmv.w.x f10, x20
    fcvt.w.s x21, f10
    li x22, 4                  # Rounds to 4 (even)
    bne x21, x22, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 7: -2.5 → -2 (round to nearest even)
    #===========================================
    li x23, 0xC0200000         # -2.5
    fmv.w.x f11, x23
    fcvt.w.s x24, f11
    li x25, -2                 # Rounds to -2 (even)
    bne x24, x25, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 8: 127.0 → 127
    #===========================================
    li x26, 0x42FE0000         # 127.0
    fmv.w.x f12, x26
    fcvt.w.s x27, f12
    li x28, 127
    bne x27, x28, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 9: 1000.0 → 1000
    #===========================================
    li x5, 0x447A0000          # 1000.0
    fmv.w.x f13, x5
    fcvt.w.s x6, f13
    li x7, 1000
    bne x6, x7, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 10: -1000.0 → -1000
    #===========================================
    li x8, 0xC47A0000          # -1000.0
    fmv.w.x f14, x8
    fcvt.w.s x9, f14
    li x10, -1000
    bne x9, x10, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 11: 0.7 → 1 (round up)
    #===========================================
    li x11, 0x3F333333         # 0.7
    fmv.w.x f15, x11
    fcvt.w.s x12, f15
    li x13, 1
    bne x12, x13, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 12: 0.4 → 0 (round down)
    #===========================================
    li x14, 0x3ECCCCCD         # 0.4
    fmv.w.x f16, x14
    fcvt.w.s x15, f16
    li x16, 0
    bne x15, x16, test_failed
    addi x31, x31, 1

    #===========================================
    # FCVT.WU.S Tests (Float → Unsigned Int)
    #===========================================

    #===========================================
    # Test 13: 0.0 → 0 (unsigned)
    #===========================================
    li x17, 0x00000000         # +0.0
    fmv.w.x f17, x17
    fcvt.wu.s x18, f17
    li x19, 0
    bne x18, x19, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 14: 1.0 → 1 (unsigned)
    #===========================================
    li x20, 0x3F800000         # 1.0
    fmv.w.x f18, x20
    fcvt.wu.s x21, f18
    li x22, 1
    bne x21, x22, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 15: 255.0 → 255 (unsigned)
    #===========================================
    li x23, 0x437F0000         # 255.0
    fmv.w.x f19, x23
    fcvt.wu.s x24, f19
    li x25, 255
    bne x24, x25, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 16: 4294967040.0 → 4294967040 (large unsigned)
    # This is close to UINT_MAX
    #===========================================
    li x26, 0x4F7FFFFF         # 4294967040.0 (max representable < UINT_MAX)
    fmv.w.x f20, x26
    fcvt.wu.s x27, f20
    li x28, 0xFFFFFF00         # 4294967040
    bne x27, x28, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 17: -1.0 → 0 (unsigned, negative saturates to 0)
    # NOTE: Negative values should saturate to 0 for unsigned conversion
    #===========================================
    li x5, 0xBF800000          # -1.0
    fmv.w.x f21, x5
    fcvt.wu.s x6, f21
    li x7, 0                   # Should saturate to 0
    bne x6, x7, test_failed
    addi x31, x31, 1

    #===========================================
    # Test 18: 1.5 → 2 (unsigned, round to nearest)
    #===========================================
    li x8, 0x3FC00000          # 1.5
    fmv.w.x f22, x8
    fcvt.wu.s x9, f22
    li x10, 2
    bne x9, x10, test_failed
    addi x31, x31, 1

    # All tests passed!
    j test_passed

test_failed:
    # Set failure indicator
    li x30, 0xDEADBEEF
    # x31 shows how many tests passed before failure
    ebreak

test_passed:
    # Set success indicator (should have 18 passed tests)
    li x30, 0x600DCAFE
    # x31 should contain 18
    ebreak
