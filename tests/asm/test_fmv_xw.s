# Test FMV.X.W instruction (FP to Integer register move)
# This test verifies that FMV.X.W correctly transfers bit patterns
# from FP registers to integer registers without conversion

.section .text
.globl _start

_start:
    # Initialize test values
    li      t0, 0x3F800000      # 1.0 in IEEE 754 single-precision
    li      t1, 0x40000000      # 2.0 in IEEE 754 single-precision
    li      t2, 0xC0400000      # -3.0 in IEEE 754 single-precision

    # Move integer values to FP registers using FMV.W.X
    fmv.w.x f1, t0              # f1 = 1.0
    fmv.w.x f2, t1              # f2 = 2.0
    fmv.w.x f3, t2              # f3 = -3.0

    # Test FMV.X.W: Move FP register bits to integer register
    fmv.x.w a0, f1              # a0 should be 0x3F800000
    fmv.x.w a1, f2              # a1 should be 0x40000000
    fmv.x.w a3, f3              # a3 should be 0xC0400000 (sign-extended)

    # Verify results
    li      t3, 0x3F800000
    bne     a0, t3, fail

    li      t3, 0x40000000
    bne     a1, t3, fail

    li      t3, 0xC0400000
    bne     a3, t3, fail

    # Success
    li      a0, 42              # Success marker
    j       end

fail:
    li      a0, 0               # Failure marker

end:
    # Infinite loop
    j       end
