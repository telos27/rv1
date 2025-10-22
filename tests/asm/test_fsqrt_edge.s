.section .text
.globl _start

_start:
    # Test edge cases for FSQRT that might fail

    # Test 1: sqrt(0.0) = 0.0
    li      t0, 0x00000000      # +0.0
    fmv.w.x f10, t0
    fsqrt.s f11, f10
    fmv.x.w a0, f11             # Should be 0x00000000

    # Test 2: sqrt(-0.0) = -0.0
    li      t0, 0x80000000      # -0.0
    fmv.w.x f12, t0
    fsqrt.s f13, f12
    fmv.x.w a1, f13             # Should be 0x80000000

    # Test 3: sqrt(INF) = INF
    li      t0, 0x7F800000      # +INF
    fmv.w.x f14, t0
    fsqrt.s f15, f14
    fmv.x.w a2, f15             # Should be 0x7F800000

    # Test 4: sqrt(-1.0) = NaN (invalid)
    li      t0, 0xBF800000      # -1.0
    fmv.w.x f16, t0
    fsqrt.s f17, f16
    fmv.x.w a3, f17             # Should be NaN (0x7FC00000)

    # Test 5: sqrt(NaN) = NaN
    li      t0, 0x7FC00001      # NaN
    fmv.w.x f18, t0
    fsqrt.s f19, f18
    fmv.x.w a4, f19             # Should be NaN

    # Test 6: sqrt(very small denormal)
    li      t0, 0x00000001      # Smallest denormal
    fmv.w.x f20, t0
    fsqrt.s f21, f20
    fmv.x.w a5, f21             # Should produce small result

    # Success marker
    li      t3, 0xdeadbeef

    # Exit
    j       _start
