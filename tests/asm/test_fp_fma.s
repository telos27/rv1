# Floating-Point FMA (Fused Multiply-Add) Test
# Tests: FMADD.S, FMSUB.S, FNMSUB.S, FNMADD.S
# FMA operations perform (a*b)+c with single rounding (more accurate than MUL+ADD)

.section .data
.align 2
fp_data:
    .word 0x3F800000    # 1.0
    .word 0x40000000    # 2.0
    .word 0x40400000    # 3.0
    .word 0x40800000    # 4.0
    .word 0x40A00000    # 5.0
    .word 0x3F000000    # 0.5
    .word 0xBF800000    # -1.0
    .word 0xC0000000    # -2.0

.section .text
.globl _start

_start:
    la x10, fp_data

    # Load test values
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = 2.0
    flw f2, 8(x10)      # f2 = 3.0
    flw f3, 12(x10)     # f3 = 4.0
    flw f4, 16(x10)     # f4 = 5.0
    flw f5, 20(x10)     # f5 = 0.5
    flw f6, 24(x10)     # f6 = -1.0
    flw f7, 28(x10)     # f7 = -2.0

    # Test 1: FMADD.S - Fused multiply-add
    # FMADD.S fd, rs1, rs2, rs3: fd = (rs1 * rs2) + rs3

    # f10 = (2.0 * 3.0) + 4.0 = 6.0 + 4.0 = 10.0 (0x41200000)
    fmadd.s f10, f1, f2, f3

    # f11 = (1.0 * 2.0) + 3.0 = 2.0 + 3.0 = 5.0 (0x40A00000)
    fmadd.s f11, f0, f1, f2

    # f12 = (4.0 * 0.5) + 1.0 = 2.0 + 1.0 = 3.0 (0x40400000)
    fmadd.s f12, f3, f5, f0

    # Test 2: FMSUB.S - Fused multiply-subtract
    # FMSUB.S fd, rs1, rs2, rs3: fd = (rs1 * rs2) - rs3

    # f13 = (2.0 * 3.0) - 4.0 = 6.0 - 4.0 = 2.0 (0x40000000)
    fmsub.s f13, f1, f2, f3

    # f14 = (4.0 * 2.0) - 3.0 = 8.0 - 3.0 = 5.0 (0x40A00000)
    fmsub.s f14, f3, f1, f2

    # f15 = (5.0 * 1.0) - 2.0 = 5.0 - 2.0 = 3.0 (0x40400000)
    fmsub.s f15, f4, f0, f1

    # Test 3: FNMSUB.S - Fused negated multiply-subtract
    # FNMSUB.S fd, rs1, rs2, rs3: fd = -(rs1 * rs2) + rs3

    # f16 = -(2.0 * 3.0) + 10.0 = -6.0 + 10.0 = 4.0 (0x40800000)
    fnmsub.s f16, f1, f2, f10

    # f17 = -(1.0 * 4.0) + 5.0 = -4.0 + 5.0 = 1.0 (0x3F800000)
    fnmsub.s f17, f0, f3, f4

    # f18 = -(2.0 * 2.0) + 4.0 = -4.0 + 4.0 = 0.0 (0x00000000)
    fnmsub.s f18, f1, f1, f3

    # Test 4: FNMADD.S - Fused negated multiply-add
    # FNMADD.S fd, rs1, rs2, rs3: fd = -(rs1 * rs2) - rs3

    # f19 = -(2.0 * 3.0) - 4.0 = -6.0 - 4.0 = -10.0 (0xC1200000)
    fnmadd.s f19, f1, f2, f3

    # f20 = -(1.0 * 2.0) - 3.0 = -2.0 - 3.0 = -5.0 (0xC0A00000)
    fnmadd.s f20, f0, f1, f2

    # f21 = -(4.0 * 0.5) - 1.0 = -2.0 - 1.0 = -3.0 (0xC0400000)
    fnmadd.s f21, f3, f5, f0

    # Test 5: FMA with negative operands
    # f22 = (-1.0 * 2.0) + 3.0 = -2.0 + 3.0 = 1.0 (0x3F800000)
    fmadd.s f22, f6, f1, f2

    # f23 = (2.0 * -2.0) + 5.0 = -4.0 + 5.0 = 1.0 (0x3F800000)
    fmadd.s f23, f1, f7, f4

    # Verify results using FMV.X.W
    fmv.x.w x11, f10    # Should be 10.0 = 0x41200000
    fmv.x.w x12, f11    # Should be 5.0  = 0x40A00000
    fmv.x.w x13, f13    # Should be 2.0  = 0x40000000
    fmv.x.w x14, f16    # Should be 4.0  = 0x40800000
    fmv.x.w x15, f19    # Should be -10.0 = 0xC1200000

    # Verification checks
    li x20, 0x41200000
    bne x11, x20, fail  # Check f10 = 10.0

    li x20, 0x40A00000
    bne x12, x20, fail  # Check f11 = 5.0

    li x20, 0x40000000
    bne x13, x20, fail  # Check f13 = 2.0

    li x20, 0x40800000
    bne x14, x20, fail  # Check f16 = 4.0

    li x20, 0xC1200000
    bne x15, x20, fail  # Check f19 = -10.0

    # All tests passed
    li x28, 0xFEEDFACE
    ebreak

fail:
    li x28, 0xDEADDEAD

end:
    ebreak

# Expected Results:
# FMADD tests:
# f10 = 10.0 (0x41200000) - (2.0*3.0)+4.0
# f11 = 5.0  (0x40A00000) - (1.0*2.0)+3.0
# f12 = 3.0  (0x40400000) - (4.0*0.5)+1.0
#
# FMSUB tests:
# f13 = 2.0  (0x40000000) - (2.0*3.0)-4.0
# f14 = 5.0  (0x40A00000) - (4.0*2.0)-3.0
# f15 = 3.0  (0x40400000) - (5.0*1.0)-2.0
#
# FNMSUB tests:
# f16 = 4.0  (0x40800000) - -(2.0*3.0)+10.0
# f17 = 1.0  (0x3F800000) - -(1.0*4.0)+5.0
# f18 = 0.0  (0x00000000) - -(2.0*2.0)+4.0
#
# FNMADD tests:
# f19 = -10.0 (0xC1200000) - -(2.0*3.0)-4.0
# f20 = -5.0  (0xC0A00000) - -(1.0*2.0)-3.0
# f21 = -3.0  (0xC0400000) - -(4.0*0.5)-1.0
#
# With negatives:
# f22 = 1.0  (0x3F800000) - (-1.0*2.0)+3.0
# f23 = 1.0  (0x3F800000) - (2.0*-2.0)+5.0
#
# x28 = 0xFEEDFACE (success)
