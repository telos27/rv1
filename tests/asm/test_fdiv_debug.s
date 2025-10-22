.section .text
.globl _start

_start:
    # Test 1: 1.0 / 1.0 = 1.0
    li      t0, 0x3f800000      # 1.0
    fmv.w.x f10, t0
    fmv.w.x f11, t0
    fdiv.s  f12, f10, f11
    fmv.x.w a0, f12             # Should be 0x3f800000 (1.0)

    # Test 2: 4.0 / 2.0 = 2.0
    li      t0, 0x40800000      # 4.0
    li      t1, 0x40000000      # 2.0
    fmv.w.x f13, t0
    fmv.w.x f14, t1
    fdiv.s  f15, f13, f14
    fmv.x.w a1, f15             # Should be 0x40000000 (2.0)

    # Test 3: 10.0 / 5.0 = 2.0
    li      t0, 0x41200000      # 10.0
    li      t1, 0x40a00000      # 5.0
    fmv.w.x f16, t0
    fmv.w.x f17, t1
    fdiv.s  f18, f16, f17
    fmv.x.w a2, f18             # Should be 0x40000000 (2.0)

    # Test 4: Division by small number
    li      t0, 0x3f800000      # 1.0
    li      t1, 0x40000000      # 2.0
    fmv.w.x f19, t0
    fmv.w.x f20, t1
    fdiv.s  f21, f19, f20
    fmv.x.w a3, f21             # Should be 0x3f000000 (0.5)

    # Success marker
    li      t3, 0xdeadbeef

    # Exit
    j       _start
