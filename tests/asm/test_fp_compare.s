# Floating-Point Compare Test
# Tests: FEQ.S, FLT.S, FLE.S
# Tests the critical fix for compare operation selection (funct3)

.section .data
.align 2
fp_values:
    .word 0x3F800000    # 1.0
    .word 0x40000000    # 2.0
    .word 0x40400000    # 3.0
    .word 0x3F800000    # 1.0 (duplicate for equality test)
    .word 0xBF800000    # -1.0
    .word 0x00000000    # 0.0
    .word 0x7F800000    # +Infinity
    .word 0xFF800000    # -Infinity
    .word 0x7FC00000    # NaN (quiet)

.section .text
.globl _start

_start:
    # Load base address
    la x10, fp_values

    # Load test values
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = 2.0
    flw f2, 8(x10)      # f2 = 3.0
    flw f3, 12(x10)     # f3 = 1.0 (equal to f0)
    flw f4, 16(x10)     # f4 = -1.0
    flw f5, 20(x10)     # f5 = 0.0
    flw f6, 24(x10)     # f6 = +Inf
    flw f7, 28(x10)     # f7 = -Inf
    flw f8, 32(x10)     # f8 = NaN

    # Test 1: FEQ.S - Floating-point equal
    # x11 = (f0 == f3) = (1.0 == 1.0) = 1 (true)
    feq.s x11, f0, f3

    # x12 = (f0 == f1) = (1.0 == 2.0) = 0 (false)
    feq.s x12, f0, f1

    # x13 = (f5 == f5) = (0.0 == 0.0) = 1 (true)
    feq.s x13, f5, f5

    # x14 = (f8 == f8) = (NaN == NaN) = 0 (false, NaN never equals anything)
    feq.s x14, f8, f8

    # Test 2: FLT.S - Floating-point less than
    # x15 = (f0 < f1) = (1.0 < 2.0) = 1 (true)
    flt.s x15, f0, f1

    # x16 = (f1 < f0) = (2.0 < 1.0) = 0 (false)
    flt.s x16, f1, f0

    # x17 = (f4 < f0) = (-1.0 < 1.0) = 1 (true)
    flt.s x17, f4, f0

    # x18 = (f0 < f0) = (1.0 < 1.0) = 0 (false, not strictly less)
    flt.s x18, f0, f0

    # x19 = (f7 < f5) = (-Inf < 0.0) = 1 (true)
    flt.s x19, f7, f5

    # Test 3: FLE.S - Floating-point less than or equal
    # x20 = (f0 <= f1) = (1.0 <= 2.0) = 1 (true)
    fle.s x20, f0, f1

    # x21 = (f0 <= f3) = (1.0 <= 1.0) = 1 (true, equal)
    fle.s x21, f0, f3

    # x22 = (f1 <= f0) = (2.0 <= 1.0) = 0 (false)
    fle.s x22, f1, f0

    # x23 = (f6 <= f6) = (+Inf <= +Inf) = 1 (true, equal)
    fle.s x23, f6, f6

    # Test 4: Comparison with special values
    # x24 = (f6 < f0) = (+Inf < 1.0) = 0 (false, +Inf is largest)
    flt.s x24, f6, f0

    # x25 = (f0 < f6) = (1.0 < +Inf) = 1 (true)
    flt.s x25, f0, f6

    # x26 = (NaN < 1.0) = 0 (false, NaN comparisons always false except !=)
    flt.s x26, f8, f0

    # x27 = (1.0 < NaN) = 0 (false)
    flt.s x27, f0, f8

    # Set success marker
    li x28, 0xC0FFEE00

    # Verify expected results
    # x11 should be 1 (1.0 == 1.0)
    li x29, 1
    bne x11, x29, fail

    # x12 should be 0 (1.0 != 2.0)
    li x29, 0
    bne x12, x29, fail

    # x15 should be 1 (1.0 < 2.0)
    li x29, 1
    bne x15, x29, fail

    # x16 should be 0 (2.0 not < 1.0)
    li x29, 0
    bne x16, x29, fail

    # x20 should be 1 (1.0 <= 2.0)
    li x29, 1
    bne x20, x29, fail

    # x21 should be 1 (1.0 <= 1.0)
    bne x21, x29, fail

    # All tests passed
    li x28, 0xFEEDFACE
    j end

fail:
    li x28, 0xDEADDEAD

end:
    j end

# Expected Results:
# x11 = 1  (FEQ: 1.0 == 1.0)
# x12 = 0  (FEQ: 1.0 != 2.0)
# x13 = 1  (FEQ: 0.0 == 0.0)
# x14 = 0  (FEQ: NaN != NaN)
# x15 = 1  (FLT: 1.0 < 2.0)
# x16 = 0  (FLT: 2.0 not < 1.0)
# x17 = 1  (FLT: -1.0 < 1.0)
# x18 = 0  (FLT: 1.0 not < 1.0)
# x19 = 1  (FLT: -Inf < 0.0)
# x20 = 1  (FLE: 1.0 <= 2.0)
# x21 = 1  (FLE: 1.0 <= 1.0)
# x22 = 0  (FLE: 2.0 not <= 1.0)
# x23 = 1  (FLE: +Inf <= +Inf)
# x24 = 0  (FLT: +Inf not < 1.0)
# x25 = 1  (FLT: 1.0 < +Inf)
# x26 = 0  (FLT: NaN comparisons false)
# x27 = 0  (FLT: NaN comparisons false)
# x28 = 0xFEEDFACE (all tests passed)
