# Simple FP Compare Test - Debug Version
# Tests just one FEQ operation

.section .data
.align 2
fp_values:
    .word 0x3F800000    # 1.0
    .word 0x3F800000    # 1.0 (duplicate for equality test)

.section .text
.globl _start

_start:
    # Load base address
    la x10, fp_values
    
    # Load test values
    flw f0, 0(x10)      # f0 = 1.0
    flw f1, 4(x10)      # f1 = 1.0
    
    # Test: FEQ.S - Should return 1 (true)
    feq.s x11, f0, f1
    
    # Check result
    li x12, 1           # Expected value
    
    # Debug: Store both values
    mv x13, x11         # x13 = actual result
    mv x14, x12         # x14 = expected result
    
    # Compare
    bne x11, x12, fail
    
    # Success
    li x28, 0xFEEDFACE
    j end
    
fail:
    li x28, 0xDEADDEAD
    
end:
    j end
