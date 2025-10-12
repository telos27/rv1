# Floating-Point Load-Use Hazard Test
# Tests the critical fix for FP load-use hazard detection
# Verifies that pipeline correctly stalls when FP load is followed by FP operation

.section .data
.align 2
fp_values:
    .word 0x3F800000    # 1.0
    .word 0x40000000    # 2.0
    .word 0x40400000    # 3.0
    .word 0x40800000    # 4.0

results:
    .space 16

.section .text
.globl _start

_start:
    la x10, fp_values
    la x11, results

    # Test 1: FP Load followed immediately by FP ADD (load-use hazard)
    # Without hazard detection, f5 would use stale/undefined f0 value
    # With hazard detection, pipeline stalls until FLW completes
    flw f0, 0(x10)      # Load 1.0 into f0
    fadd.s f5, f0, f0   # HAZARD: f0 used immediately after load
                        # Expected: stall 1 cycle, then compute 1.0 + 1.0 = 2.0
    fsw f5, 0(x11)      # Store result

    # Test 2: FP Load -> NOP -> FP ADD (no hazard, forwarding works)
    flw f1, 4(x10)      # Load 2.0 into f1
    nop                 # Allow load to complete
    fadd.s f6, f1, f1   # No hazard: 2.0 + 2.0 = 4.0
    fsw f6, 4(x11)

    # Test 3: Two consecutive loads followed by FP operation using both
    flw f2, 8(x10)      # Load 3.0 into f2
    flw f3, 12(x10)     # Load 4.0 into f3
    fadd.s f7, f2, f3   # DOUBLE HAZARD: both f2 and f3 just loaded
                        # Expected: stalls, then 3.0 + 4.0 = 7.0 (0x40E00000)
    fsw f7, 8(x11)

    # Test 4: FP Load followed by FP multiply (different operation type)
    flw f4, 0(x10)      # Load 1.0
    fmul.s f8, f4, f1   # HAZARD: f4 just loaded, multiply with f1 (2.0)
                        # Expected: stall, then 1.0 * 2.0 = 2.0
    fsw f8, 12(x11)

    # Test 5: FP Load followed by FMA (3-operand, tests rs3 hazard)
    flw f9, 4(x10)      # Load 2.0 into f9
    # FMADD: f10 = (f9 * f1) + f2 = (2.0 * 2.0) + 3.0 = 7.0
    fmadd.s f10, f9, f1, f2  # HAZARD on f9 (rs1)

    # Test 6: FP Load into rs2 of FMA
    flw f11, 8(x10)     # Load 3.0 into f11
    # FMADD: f12 = (f1 * f11) + f2 = (2.0 * 3.0) + 3.0 = 9.0 (0x41100000)
    fmadd.s f12, f1, f11, f2  # HAZARD on f11 (rs2)

    # Test 7: FP Load into rs3 of FMA
    flw f13, 12(x10)    # Load 4.0 into f13
    # FMADD: f14 = (f1 * f2) + f13 = (2.0 * 3.0) + 4.0 = 10.0 (0x41200000)
    fmadd.s f14, f1, f2, f13  # HAZARD on f13 (rs3)

    # Verify results using FMV.X.W
    fmv.x.w x12, f5     # Should be 2.0 = 0x40000000
    fmv.x.w x13, f6     # Should be 4.0 = 0x40800000
    fmv.x.w x14, f7     # Should be 7.0 = 0x40E00000
    fmv.x.w x15, f8     # Should be 2.0 = 0x40000000

    # Check f5 = 2.0
    li x20, 0x40000000
    bne x12, x20, fail

    # Check f6 = 4.0
    li x20, 0x40800000
    bne x13, x20, fail

    # Check f7 = 7.0
    li x20, 0x40E00000
    bne x14, x20, fail

    # Check f8 = 2.0
    li x20, 0x40000000
    bne x15, x20, fail

    # All tests passed
    li x28, 0xFEEDFACE
    j end

fail:
    li x28, 0xDEADDEAD

end:
    j end

# Expected Results (if hazard detection works correctly):
# f5  = 2.0  (0x40000000) - load-use hazard handled
# f6  = 4.0  (0x40800000) - no hazard
# f7  = 7.0  (0x40E00000) - double load-use hazard handled
# f8  = 2.0  (0x40000000) - load-use before multiply
# f10 = 7.0  (0x40E00000) - FMA rs1 hazard
# f12 = 9.0  (0x41100000) - FMA rs2 hazard
# f14 = 10.0 (0x41200000) - FMA rs3 hazard
# x28 = 0xFEEDFACE - all tests passed
#
# If hazard detection fails:
# - Results will be incorrect (using stale/undefined register values)
# - x28 = 0xDEADDEAD - test failed
