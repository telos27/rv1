# Test FCVT.S.W with negative integers
# Verify INT→FP conversion handles negative values correctly

.section .text
.globl _start

_start:
    # Test -1: Expected 0xBF800000 (-1.0)
    li x5, -1
    fcvt.s.w f5, x5
    fmv.x.w a0, f5

    # Test -2: Expected 0xC0000000 (-2.0)
    li x6, -2
    fcvt.s.w f6, x6
    fmv.x.w a1, f6

    # Test -127: Expected 0xC2FE0000 (-127.0)
    li x7, -127
    fcvt.s.w f7, x7
    fmv.x.w a2, f7

    # Test -128: Expected 0xC3000000 (-128.0)
    li x8, -128
    fcvt.s.w f8, x8
    fmv.x.w a3, f8

    # Test -256: Expected 0xC3800000 (-256.0)
    li x9, -256
    fcvt.s.w f9, x9
    fmv.x.w a4, f9

    # Test -1000: Expected 0xC47A0000 (-1000.0)
    li x10, -1000
    fcvt.s.w f10, x10
    fmv.x.w a5, f10

    # Exit
    li a7, 93
    ecall

.section .data
