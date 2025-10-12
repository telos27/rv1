# Basic Floating-Point Test
# Tests: FADD.S, FSUB.S, FMUL.S, FDIV.S, FLW, FSW
# Expected behavior: Basic FP arithmetic operations with known results

.section .data
.align 2
fp_data:
    .word 0x3F800000    # 1.0 in IEEE 754 single-precision
    .word 0x40000000    # 2.0
    .word 0x40400000    # 3.0
    .word 0x40800000    # 4.0
    .word 0x3F000000    # 0.5
    .word 0x00000000    # 0.0
    .word 0xBF800000    # -1.0
    .word 0xC0000000    # -2.0

results:
    .space 64           # Space for results (16 words)

.section .text
.globl _start

_start:
    # Load base address of data
    la x10, fp_data
    la x11, results

    # Test 1: Load floating-point values
    # FLW f0, offset(x10) - Load word into FP register
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = 2.0
    flw f2, 8(x10)      # f2 = 3.0
    flw f3, 12(x10)     # f3 = 4.0
    flw f4, 16(x10)     # f4 = 0.5

    # Test 2: FADD.S - Floating-point addition
    # f5 = f0 + f1 = 1.0 + 2.0 = 3.0
    fadd.s f5, f0, f1
    fsw f5, 0(x11)      # Store result

    # f6 = f1 + f2 = 2.0 + 3.0 = 5.0 (0x40A00000)
    fadd.s f6, f1, f2
    fsw f6, 4(x11)

    # Test 3: FSUB.S - Floating-point subtraction
    # f7 = f2 - f0 = 3.0 - 1.0 = 2.0
    fsub.s f7, f2, f0
    fsw f7, 8(x11)

    # f8 = f3 - f1 = 4.0 - 2.0 = 2.0
    fsub.s f8, f3, f1
    fsw f8, 12(x11)

    # Test 4: FMUL.S - Floating-point multiplication
    # f9 = f1 * f2 = 2.0 * 3.0 = 6.0 (0x40C00000)
    fmul.s f9, f1, f2
    fsw f9, 16(x11)

    # f10 = f3 * f4 = 4.0 * 0.5 = 2.0
    fmul.s f10, f3, f4
    fsw f10, 20(x11)

    # Test 5: FDIV.S - Floating-point division
    # f11 = f3 / f1 = 4.0 / 2.0 = 2.0
    fdiv.s f11, f3, f1
    fsw f11, 24(x11)

    # f12 = f2 / f0 = 3.0 / 1.0 = 3.0
    fdiv.s f12, f2, f0
    fsw f12, 28(x11)

    # Test 6: Check results using integer moves
    # Move FP results to integer registers for verification
    fmv.x.w x12, f5     # Should be 3.0 = 0x40400000
    fmv.x.w x13, f6     # Should be 5.0 = 0x40A00000
    fmv.x.w x14, f7     # Should be 2.0 = 0x40000000
    fmv.x.w x15, f9     # Should be 6.0 = 0x40C00000

    # Set success flag
    li x28, 0xDEADBEEF
    nop
    nop
    nop

    # End of test - signal success with EBREAK
    ebreak

# Expected Results:
# f5  (results+0)  = 3.0  = 0x40400000
# f6  (results+4)  = 5.0  = 0x40A00000
# f7  (results+8)  = 2.0  = 0x40000000
# f8  (results+12) = 2.0  = 0x40000000
# f9  (results+16) = 6.0  = 0x40C00000
# f10 (results+20) = 2.0  = 0x40000000
# f11 (results+24) = 2.0  = 0x40000000
# f12 (results+28) = 3.0  = 0x40400000
#
# x12 = 0x40400000 (3.0)
# x13 = 0x40A00000 (5.0)
# x14 = 0x40000000 (2.0)
# x15 = 0x40C00000 (6.0)
# x28 = 0xDEADBEEF (success marker)
