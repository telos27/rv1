# Test Edge Cases: Floating-Point Special Values
# Tests NaN propagation, Infinity, signed zeros, and denormals
# RISC-V RV32F/D Extension Edge Case Test

.section .text
.globl _start

_start:
    # Test base address for results
    lui x10, 0x01000       # x10 = 0x01000000 (test memory base)

    #===========================================
    # Test 1: Positive and Negative Zero
    #===========================================
    # Create +0.0
    fcvt.s.w f0, x0        # f0 = +0.0

    # Create -0.0 (negate +0.0)
    fneg.s f1, f0          # f1 = -0.0

    # Store both zeros
    fsw f0, 0(x10)         # Store +0.0
    fsw f1, 4(x10)         # Store -0.0

    # +0.0 == -0.0 should be true
    feq.s x5, f0, f1       # x5 = 1 (equal)
    sw x5, 8(x10)          # Store comparison result

    # +0.0 + -0.0 = +0.0
    fadd.s f2, f0, f1      # f2 = +0.0
    fsw f2, 12(x10)        # Store result

    # +0.0 - -0.0 = +0.0
    fsub.s f3, f0, f1      # f3 = +0.0
    fsw f3, 16(x10)        # Store result

    # -0.0 - +0.0 = -0.0
    fsub.s f4, f1, f0      # f4 = -0.0
    fsw f4, 20(x10)        # Store result

    #===========================================
    # Test 2: Positive Infinity
    #===========================================
    # Create +Inf by dividing positive by zero
    li x5, 1
    fcvt.s.w f5, x5        # f5 = 1.0
    fdiv.s f6, f5, f0      # f6 = +Inf (1.0 / +0.0)
    fsw f6, 24(x10)        # Store +Inf

    # Classify +Inf (should return bit 7 = positive infinity)
    fclass.s x6, f6
    sw x6, 28(x10)         # Store classification

    # +Inf + 1.0 = +Inf
    fadd.s f7, f6, f5      # f7 = +Inf
    fsw f7, 32(x10)        # Store result

    # +Inf - 1.0 = +Inf
    fsub.s f8, f6, f5      # f8 = +Inf
    fsw f8, 36(x10)        # Store result

    # +Inf × 2.0 = +Inf
    li x7, 2
    fcvt.s.w f9, x7        # f9 = 2.0
    fmul.s f10, f6, f9     # f10 = +Inf
    fsw f10, 40(x10)       # Store result

    # +Inf / 2.0 = +Inf
    fdiv.s f11, f6, f9     # f11 = +Inf
    fsw f11, 44(x10)       # Store result

    #===========================================
    # Test 3: Negative Infinity
    #===========================================
    # Create -Inf by negating +Inf
    fneg.s f12, f6         # f12 = -Inf
    fsw f12, 48(x10)       # Store -Inf

    # Classify -Inf (should return bit 0 = negative infinity)
    fclass.s x8, f12
    sw x8, 52(x10)         # Store classification

    # -Inf + 1.0 = -Inf
    fadd.s f13, f12, f5    # f13 = -Inf
    fsw f13, 56(x10)       # Store result

    # -Inf × -1.0 = +Inf
    li x9, -1
    fcvt.s.w f14, x9       # f14 = -1.0
    fmul.s f15, f12, f14   # f15 = +Inf
    fsw f15, 60(x10)       # Store result

    #===========================================
    # Test 4: Infinity Arithmetic Edge Cases
    #===========================================
    # +Inf + +Inf = +Inf
    fadd.s f16, f6, f6     # f16 = +Inf
    fsw f16, 64(x10)       # Store result

    # +Inf - -Inf = +Inf
    fsub.s f17, f6, f12    # f17 = +Inf
    fsw f17, 68(x10)       # Store result

    # +Inf - +Inf = NaN (indeterminate)
    fsub.s f18, f6, f6     # f18 = NaN
    fsw f18, 72(x10)       # Store NaN

    # +Inf / +Inf = NaN
    fdiv.s f19, f6, f6     # f19 = NaN
    fsw f19, 76(x10)       # Store NaN

    # 0.0 × +Inf = NaN
    fmul.s f20, f0, f6     # f20 = NaN
    fsw f20, 80(x10)       # Store NaN

    #===========================================
    # Test 5: NaN Creation and Propagation
    #===========================================
    # Create NaN: sqrt(-1.0)
    fsqrt.s f21, f14       # f21 = NaN (sqrt of negative)
    fsw f21, 84(x10)       # Store NaN

    # Classify NaN (should return bit 9 or 8 for qNaN/sNaN)
    fclass.s x11, f21
    sw x11, 88(x10)        # Store classification

    # NaN + anything = NaN (propagation test)
    fadd.s f22, f21, f5    # f22 = NaN (NaN + 1.0)
    fsw f22, 92(x10)       # Store NaN

    # anything + NaN = NaN
    fadd.s f23, f5, f21    # f23 = NaN (1.0 + NaN)
    fsw f23, 96(x10)       # Store NaN

    # NaN × 0.0 = NaN
    fmul.s f24, f21, f0    # f24 = NaN
    fsw f24, 100(x10)      # Store NaN

    # NaN / NaN = NaN
    fdiv.s f25, f21, f21   # f25 = NaN
    fsw f25, 104(x10)      # Store NaN

    #===========================================
    # Test 6: NaN Comparison Behavior
    #===========================================
    # NaN == NaN should be false
    feq.s x12, f21, f21    # x12 = 0 (false, per IEEE 754)
    sw x12, 108(x10)       # Store result

    # NaN < 1.0 should be false
    flt.s x13, f21, f5     # x13 = 0 (false)
    sw x13, 112(x10)       # Store result

    # 1.0 < NaN should be false
    flt.s x14, f5, f21     # x14 = 0 (false)
    sw x14, 116(x10)       # Store result

    # NaN <= NaN should be false
    fle.s x15, f21, f21    # x15 = 0 (false)
    sw x15, 120(x10)       # Store result

    #===========================================
    # Test 7: Min/Max with Special Values
    #===========================================
    # fmin(1.0, +Inf) = 1.0
    fmin.s f26, f5, f6     # f26 = 1.0
    fsw f26, 124(x10)      # Store result

    # fmax(1.0, +Inf) = +Inf
    fmax.s f27, f5, f6     # f27 = +Inf
    fsw f27, 128(x10)      # Store result

    # fmin(+0.0, -0.0) = -0.0 or +0.0 (implementation-defined)
    fmin.s f28, f0, f1     # f28 = -0.0 (typically)
    fsw f28, 132(x10)      # Store result

    # fmax(+0.0, -0.0) = +0.0 or -0.0 (implementation-defined)
    fmax.s f29, f0, f1     # f29 = +0.0 (typically)
    fsw f29, 136(x10)      # Store result

    # fmin(NaN, 1.0) = 1.0 (per RISC-V spec, return non-NaN)
    fmin.s f30, f21, f5    # f30 = 1.0
    fsw f30, 140(x10)      # Store result

    # fmax(NaN, 1.0) = 1.0 (per RISC-V spec, return non-NaN)
    fmax.s f31, f21, f5    # f31 = 1.0
    fsw f31, 144(x10)      # Store result

    #===========================================
    # Test 8: FMA with Special Values
    #===========================================
    # (1.0 × 2.0) + 3.0 = 5.0 (normal case)
    li x16, 3
    fcvt.s.w f0, x16       # f0 = 3.0
    fmadd.s f1, f5, f9, f0 # f1 = (1.0 × 2.0) + 3.0 = 5.0
    fsw f1, 148(x10)       # Store result

    # (+Inf × 2.0) + 1.0 = +Inf
    fmadd.s f2, f6, f9, f5 # f2 = (+Inf × 2.0) + 1.0 = +Inf
    fsw f2, 152(x10)       # Store result

    # (NaN × 1.0) + 1.0 = NaN (NaN propagates)
    fmadd.s f3, f21, f5, f5 # f3 = NaN
    fsw f3, 156(x10)       # Store result

    # (0.0 × +Inf) + 1.0 = NaN + 1.0 = NaN
    fcvt.s.w f4, x0        # f4 = +0.0
    fmadd.s f5, f4, f6, f5 # f5 = NaN (0 × Inf = NaN)
    fsw f5, 160(x10)       # Store result

    #===========================================
    # Test 9: Conversion Edge Cases
    #===========================================
    # Convert +Inf to integer (should saturate or return max)
    fcvt.w.s x17, f6       # x17 = INT_MAX (saturates)
    sw x17, 164(x10)       # Store result

    # Convert -Inf to integer
    fcvt.w.s x18, f12      # x18 = INT_MIN (saturates)
    sw x18, 168(x10)       # Store result

    # Convert NaN to integer (should return 0 or max per spec)
    fcvt.w.s x19, f21      # x19 = INT_MAX (per RISC-V spec)
    sw x19, 172(x10)       # Store result

    #===========================================
    # Test 10: Sign Injection with Special Values
    #===========================================
    # fsgnj(+1.0, -1.0) = -1.0 (copy sign)
    li x20, 1
    li x21, -1
    fcvt.s.w f7, x20       # f7 = +1.0
    fcvt.s.w f8, x21       # f8 = -1.0
    fsgnj.s f9, f7, f8     # f9 = -1.0 (copy sign from f8)
    fsw f9, 176(x10)       # Store result

    # fsgnjn(+1.0, -1.0) = +1.0 (copy negated sign)
    fsgnjn.s f10, f7, f8   # f10 = +1.0
    fsw f10, 180(x10)      # Store result

    # fsgnjx(+1.0, -1.0) = -1.0 (XOR signs)
    fsgnjx.s f11, f7, f8   # f11 = -1.0
    fsw f11, 184(x10)      # Store result

    #===========================================
    # Verification Section
    #===========================================
    # Load back critical results for verification
    lw x22, 8(x10)         # +0.0 == -0.0 comparison
    lw x23, 28(x10)        # +Inf classification
    lw x24, 108(x10)       # NaN == NaN (should be 0)
    flw f12, 72(x10)       # Load NaN from Inf - Inf

    #===========================================
    # Test Complete - Set return value
    #===========================================
    li x10, 0              # Return 0 for success

    # Infinite loop to end simulation
    j .
