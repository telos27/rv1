# Floating-Point Miscellaneous Operations Test
# Tests: FSGNJ, FSGNJN, FSGNJX, FMIN, FMAX, FCLASS, FMV.X.W, FMV.W.X

.section .data
.align 2
fp_values:
    .word 0x3F800000    # 1.0
    .word 0xBF800000    # -1.0
    .word 0x40000000    # 2.0
    .word 0xC0000000    # -2.0
    .word 0x00000000    # +0.0
    .word 0x80000000    # -0.0
    .word 0x7F800000    # +Infinity
    .word 0xFF800000    # -Infinity
    .word 0x7FC00000    # +NaN (quiet)
    .word 0x00400000    # Smallest positive subnormal

.section .text
.globl _start

_start:
    la x10, fp_values

    # Load test values
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = -1.0
    flw f2, 8(x10)      # f2 = 2.0
    flw f3, 12(x10)     # f3 = -2.0
    flw f4, 16(x10)     # f4 = +0.0
    flw f5, 20(x10)     # f5 = -0.0
    flw f6, 24(x10)     # f6 = +Inf
    flw f7, 28(x10)     # f7 = -Inf
    flw f8, 32(x10)     # f8 = NaN
    flw f9, 36(x10)     # f9 = subnormal

    # Test 1: FSGNJ.S - Sign injection
    # fd = |rs1| with sign of rs2
    # Result has magnitude of rs1, sign of rs2

    fsgnj.s f10, f0, f1  # f10 = |1.0| with sign of -1.0 = -1.0
    fsgnj.s f11, f1, f0  # f11 = |-1.0| with sign of 1.0 = 1.0
    fsgnj.s f12, f2, f2  # f12 = |2.0| with sign of 2.0 = 2.0 (no change)

    # Test 2: FSGNJN.S - Sign injection negated
    # fd = |rs1| with negated sign of rs2

    fsgnjn.s f13, f0, f1  # f13 = |1.0| with -sign of -1.0 = 1.0
    fsgnjn.s f14, f0, f0  # f14 = |1.0| with -sign of 1.0 = -1.0
    fsgnjn.s f15, f2, f3  # f15 = |2.0| with -sign of -2.0 = 2.0

    # Test 3: FSGNJX.S - Sign injection XOR
    # fd = |rs1| with sign(rs1) XOR sign(rs2)
    # Used to implement FABS (x,x) and FNEG (x,x,x with neg constant)

    fsgnjx.s f16, f0, f0  # f16 = sign(1.0) XOR sign(1.0) = 0 -> +1.0
    fsgnjx.s f17, f0, f1  # f17 = sign(1.0) XOR sign(-1.0) = 1 -> -1.0
    fsgnjx.s f18, f1, f1  # f18 = sign(-1.0) XOR sign(-1.0) = 0 -> +1.0

    # Test 4: FMIN.S - Minimum value
    # Returns smaller of two values (handles NaN, signed zero correctly)

    fmin.s f19, f0, f2   # f19 = min(1.0, 2.0) = 1.0
    fmin.s f20, f1, f3   # f20 = min(-1.0, -2.0) = -2.0
    fmin.s f21, f4, f5   # f21 = min(+0.0, -0.0) = -0.0 (0x80000000)
    fmin.s f22, f0, f8   # f22 = min(1.0, NaN) = 1.0 (non-NaN value)
    fmin.s f23, f7, f2   # f23 = min(-Inf, 2.0) = -Inf

    # Test 5: FMAX.S - Maximum value
    # Returns larger of two values

    fmax.s f24, f0, f2   # f24 = max(1.0, 2.0) = 2.0
    fmax.s f25, f1, f3   # f25 = max(-1.0, -2.0) = -1.0
    fmax.s f26, f4, f5   # f26 = max(+0.0, -0.0) = +0.0 (0x00000000)
    fmax.s f27, f0, f8   # f27 = max(1.0, NaN) = 1.0 (non-NaN value)
    fmax.s f28, f6, f2   # f28 = max(+Inf, 2.0) = +Inf

    # Test 6: FCLASS.S - Classify floating-point number
    # Returns 10-bit mask identifying number class

    fclass.s x11, f1     # x11 = class(-1.0) = negative normal (bit 0)
    fclass.s x12, f0     # x12 = class(1.0) = positive normal (bit 6)
    fclass.s x13, f6     # x13 = class(+Inf) = positive infinity (bit 7)
    fclass.s x14, f7     # x14 = class(-Inf) = negative infinity (bit 0)
    fclass.s x15, f8     # x15 = class(NaN) = quiet NaN (bit 9)
    fclass.s x16, f4     # x16 = class(+0.0) = positive zero (bit 4)
    fclass.s x17, f5     # x17 = class(-0.0) = negative zero (bit 3)
    fclass.s x18, f9     # x18 = class(subnormal) = positive subnormal (bit 5)

    # Test 7: FMV.X.W and FMV.W.X - Bitcast operations
    # These move bits without conversion

    fmv.x.w x19, f0      # x19 = 0x3F800000 (1.0 as bits)
    fmv.x.w x20, f1      # x20 = 0xBF800000 (-1.0 as bits)

    li x21, 0x40400000   # 3.0 as bits
    fmv.w.x f29, x21     # f29 = 3.0 (from integer bits)

    # Verify some results
    fmv.x.w x22, f10     # f10 should be -1.0 = 0xBF800000
    li x23, 0xBF800000
    bne x22, x23, fail

    fmv.x.w x22, f11     # f11 should be 1.0 = 0x3F800000
    li x23, 0x3F800000
    bne x22, x23, fail

    fmv.x.w x22, f19     # f19 should be 1.0 (min)
    li x23, 0x3F800000
    bne x22, x23, fail

    fmv.x.w x22, f24     # f24 should be 2.0 (max)
    li x23, 0x40000000
    bne x22, x23, fail

    # Check FCLASS results
    # Positive normal should have bit 6 set = 0x040
    andi x24, x12, 0x040
    beqz x24, fail

    # All tests passed
    li x28, 0xFEEDFACE
    j end

fail:
    li x28, 0xDEADDEAD

end:
    j end

# Expected Results:
#
# Sign injection tests:
# f10 = -1.0 (0xBF800000) - FSGNJ(1.0, -1.0)
# f11 = 1.0  (0x3F800000) - FSGNJ(-1.0, 1.0)
# f13 = 1.0  (0x3F800000) - FSGNJN(1.0, -1.0)
# f14 = -1.0 (0xBF800000) - FSGNJN(1.0, 1.0)
# f17 = -1.0 (0xBF800000) - FSGNJX(1.0, -1.0)
#
# Min/Max tests:
# f19 = 1.0  (min)
# f20 = -2.0 (min)
# f24 = 2.0  (max)
# f25 = -1.0 (max)
#
# FCLASS bit positions:
# 0: negative infinity
# 1: negative normal
# 2: negative subnormal
# 3: negative zero
# 4: positive zero
# 5: positive subnormal
# 6: positive normal
# 7: positive infinity
# 8: signaling NaN
# 9: quiet NaN
#
# x12 should have bit 6 set (positive normal 1.0)
# x13 should have bit 7 set (positive infinity)
# x15 should have bit 9 set (quiet NaN)
#
# x28 = 0xFEEDFACE (success)
