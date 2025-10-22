.section .text
.globl _start

_start:
    # Test 1: sqrt(4.0) = 2.0
    li      t0, 0x40800000      # 4.0
    fmv.w.x f10, t0
    fsqrt.s f11, f10
    fmv.x.w a0, f11             # Should be 0x40000000 (2.0)

    # Test 2: sqrt(9.0) = 3.0
    li      t0, 0x41100000      # 9.0
    fmv.w.x f12, t0
    fsqrt.s f13, f12
    fmv.x.w a1, f13             # Should be 0x40400000 (3.0)

    # Test 3: sqrt(3.14159265) ≈ 1.7724539
    li      t0, 0x40490FDB      # π
    fmv.w.x f14, t0
    fsqrt.s f15, f14
    fmv.x.w a2, f15             # Should be ≈ 0x3FE2DFC5

    # Success marker
    li      t3, 0xdeadbeef

    # Exit
    j       _start
