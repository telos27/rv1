# Floating-Point Conversion Test
# Tests: FCVT.W.S, FCVT.WU.S, FCVT.S.W, FCVT.S.WU
# Tests the re-enabled fp_converter module

.section .data
.align 2
fp_values:
    .word 0x3F800000    # 1.0
    .word 0x40000000    # 2.0
    .word 0x40490FDB    # 3.14159 (pi)
    .word 0xC0000000    # -2.0
    .word 0xBF800000    # -1.0
    .word 0x42C80000    # 100.0
    .word 0x447A0000    # 1000.0
    .word 0x3F000000    # 0.5

int_values:
    .word 42
    .word -10
    .word 0
    .word 2147483647   # Max signed int32
    .word -2147483648  # Min signed int32 (0x80000000)

.section .text
.globl _start

_start:
    la x10, fp_values
    la x11, int_values

    # Test 1: FCVT.W.S - Convert float to signed int32
    # Uses current rounding mode (default RNE - round to nearest, ties to even)

    flw f0, 0(x10)      # f0 = 1.0
    fcvt.w.s x12, f0    # x12 = 1

    flw f1, 4(x10)      # f1 = 2.0
    fcvt.w.s x13, f1    # x13 = 2

    flw f2, 8(x10)      # f2 = 3.14159
    fcvt.w.s x14, f2    # x14 = 3 (rounded)

    flw f3, 28(x10)     # f3 = 0.5
    fcvt.w.s x15, f3    # x15 = 0 (rounds to nearest even = 0)

    # Test 2: FCVT.W.S with negative floats
    flw f4, 12(x10)     # f4 = -2.0
    fcvt.w.s x16, f4    # x16 = -2

    flw f5, 16(x10)     # f5 = -1.0
    fcvt.w.s x17, f5    # x17 = -1

    # Test 3: FCVT.WU.S - Convert float to unsigned int32
    flw f6, 20(x10)     # f6 = 100.0
    fcvt.wu.s x18, f6   # x18 = 100

    flw f7, 24(x10)     # f7 = 1000.0
    fcvt.wu.s x19, f7   # x19 = 1000

    # Test 4: FCVT.S.W - Convert signed int32 to float
    lw x20, 0(x11)      # x20 = 42
    fcvt.s.w f10, x20   # f10 = 42.0 (0x42280000)

    lw x21, 4(x11)      # x21 = -10
    fcvt.s.w f11, x21   # f11 = -10.0 (0xC1200000)

    lw x22, 8(x11)      # x22 = 0
    fcvt.s.w f12, x22   # f12 = 0.0 (0x00000000)

    # Test 5: FCVT.S.WU - Convert unsigned int32 to float
    li x23, 255
    fcvt.s.wu f13, x23  # f13 = 255.0 (0x437F0000)

    li x24, 1024
    fcvt.s.wu f14, x24  # f14 = 1024.0 (0x44800000)

    # Test 6: Round-trip conversion (float -> int -> float)
    flw f15, 0(x10)     # f15 = 1.0
    fcvt.w.s x25, f15   # x25 = 1
    fcvt.s.w f16, x25   # f16 = 1.0 (should match f15)

    # Test 7: Verify rounding modes with RTZ (Round Towards Zero)
    # Set rounding mode to RTZ
    li x26, 0x001       # RTZ mode
    csrw 0x002, x26     # Write to frm

    flw f17, 8(x10)     # f17 = 3.14159
    fcvt.w.s x27, f17, rtz  # x27 = 3 (truncate towards zero)

    # With negative number
    li x28, 0xC0490FDB  # -3.14159 bit pattern
    fmv.w.x f18, x28    # f18 = -3.14159
    fcvt.w.s x29, f18, rtz  # x29 = -3 (truncate towards zero)

    # Verification
    # Check x12 = 1
    li x30, 1
    bne x12, x30, fail

    # Check x13 = 2
    li x30, 2
    bne x13, x30, fail

    # Check x14 = 3 (3.14159 rounded)
    li x30, 3
    bne x14, x30, fail

    # Check x16 = -2
    li x30, -2
    bne x16, x30, fail

    # Check x18 = 100
    li x30, 100
    bne x18, x30, fail

    # Check round-trip: x25 should be 1
    li x30, 1
    bne x25, x30, fail

    # Check f10 = 42.0 by moving to integer
    fmv.x.w x30, f10
    li x31, 0x42280000
    bne x30, x31, fail

    # All tests passed
    li x28, 0xFEEDFACE
    ebreak

fail:
    li x28, 0xDEADDEAD

end:
    ebreak

# Expected Results:
# Float to Int conversions:
# x12 = 1    (1.0 -> 1)
# x13 = 2    (2.0 -> 2)
# x14 = 3    (3.14159 -> 3 rounded)
# x15 = 0    (0.5 -> 0, ties to even)
# x16 = -2   (-2.0 -> -2)
# x17 = -1   (-1.0 -> -1)
# x18 = 100  (100.0 -> 100 unsigned)
# x19 = 1000 (1000.0 -> 1000 unsigned)
#
# Int to Float conversions:
# f10 = 42.0   (0x42280000)
# f11 = -10.0  (0xC1200000)
# f12 = 0.0    (0x00000000)
# f13 = 255.0  (0x437F0000)
# f14 = 1024.0 (0x44800000)
#
# Round-trip:
# f15 = 1.0 -> x25 = 1 -> f16 = 1.0 (preserved)
#
# RTZ rounding:
# x27 = 3  (3.14159 truncated)
# x29 = -3 (-3.14159 truncated)
#
# x28 = 0xFEEDFACE (success)
